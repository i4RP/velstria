import Foundation
import UIKit
import VelstriaCore

// 担当: ui-flow。画面から切り離した純粋ロジック（ユニットテスト対象）。

// MARK: - プレイヤー名

enum PlayerNameRules {
    static let minLength = 2
    static let maxLength = 12

    enum Issue: Equatable {
        case tooShort
        case tooLong
        case invalidCharacters
    }

    /// 前後の空白・改行を除いた名前。
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 問題が無ければ nil。
    static func validate(_ raw: String) -> Issue? {
        let name = normalized(raw)
        let forbidden = CharacterSet.controlCharacters.union(.newlines).union(.illegalCharacters)
        if name.unicodeScalars.contains(where: { forbidden.contains($0) }) { return .invalidCharacters }
        if name.count < minLength { return .tooShort }
        if name.count > maxLength { return .tooLong }
        return nil
    }

    static func message(_ issue: Issue) -> String {
        switch issue {
        case .tooShort: return L("\(minLength) 文字以上で入力してください", "Use at least \(minLength) characters")
        case .tooLong: return L("\(maxLength) 文字以内で入力してください", "Use at most \(maxLength) characters")
        case .invalidCharacters: return L("使用できない文字が含まれています", "Contains characters that can't be used")
        }
    }

    /// 名前の候補（シードから決定的に生成、常に規則を満たす）。
    static func suggestion(seed: UInt64, english: Bool) -> String {
        var rng = SplitMix64(seed: seed)
        if english {
            let heads = ["Nova", "Astra", "Lumen", "Vesper", "Orion", "Sable", "Cinder", "Zephyr", "Aurora", "Rune"]
            let tails = ["Blade", "Ring", "Wing", "Fang", "Spear", "Lance", "Star", "Veil", "Crest", "Arc"]
            let name = (rng.pick(heads) ?? "Nova") + (rng.pick(tails) ?? "Star")
            return String(name.prefix(maxLength))
        }
        let heads = ["星", "蒼", "紅", "月", "灰", "焔", "雷", "霧", "白", "黒", "翠", "暁"]
        let cores = ["刃", "環", "弦", "翼", "牙", "詠", "槍", "灯", "鎖", "盾", "詩", "風"]
        let tails = ["", "の旅人", "の騎士", "使い", "の守り手", "の射手"]
        let name = (rng.pick(heads) ?? "星") + (rng.pick(cores) ?? "環") + (rng.pick(tails) ?? "")
        return String(name.prefix(maxLength))
    }
}

// MARK: - オンボーディング

enum OnboardingStep: Int, CaseIterable, Comparable {
    case splash, age, terms, name, prepare, tutorial

    static func < (a: OnboardingStep, b: OnboardingStep) -> Bool { a.rawValue < b.rawValue }

    /// 起動画面の次に表示すべき最初の未完了ステップ（途中終了からの再開に使う）。
    static func firstPending(for profile: Profile) -> OnboardingStep {
        if profile.ageBracket == nil { return .age }
        if profile.acceptedTermsVersion < FeatureFlags.currentTermsVersion { return .terms }
        if PlayerNameRules.validate(profile.displayName) != nil { return .name }
        if !profile.firstResourcePrepared { return .prepare }
        return .tutorial
    }

    /// 進捗表示用の番号（起動画面は 0）。
    var stepNumber: Int { rawValue }
    static var countedSteps: Int { allCases.count - 1 }
}

/// 初回準備（UI006）で行う実処理。キャッシュを温めて初回戦闘のもたつきを防ぐ。
enum FlowWarmUp {
    /// マスターデータの参照表を一通り引き、件数を返す。
    static func touchMasterData(_ master: MasterData) -> Int {
        var count = 0
        for h in master.heroes {
            if master.hero(h.heroID) != nil { count += 1 }
            count += master.skills(forHero: h.heroID).count
        }
        for i in master.items where master.item(i.itemID) != nil { count += 1 }
        for s in master.spells where master.spell(s.spellID) != nil { count += 1 }
        for r in master.runes where master.rune(r.runeID) != nil { count += 1 }
        for c in master.cosmetics where master.cosmetic(c.cosmeticID) != nil { count += 1 }
        for s in master.store where master.storeItem(s.sku) != nil { count += 1 }
        return count
    }

    /// 表示名（英語オーバーレイ含む）を読み込む。
    static func warmTexts(_ master: MasterData) -> Int {
        var chars = 0
        for h in master.heroes { chars += MasterText.hero(h).count }
        for s in master.skills { chars += MasterText.skill(s).count }
        for i in master.items { chars += MasterText.item(i).count }
        for s in master.spells { chars += MasterText.spell(s).count }
        for r in master.runes { chars += MasterText.rune(r).count }
        for c in master.cosmetics { chars += MasterText.cosmetic(c).count }
        return chars
    }

    /// AI 同士の試合を指定秒数だけヘッドレスで回す（ナビ格子・各システムの初回コストを前払い）。戻り値は tick 数。
    static func runSimulationWarmUp(seconds: Double = 1.0, seed: UInt64 = 0x57A2_2026) -> Int {
        let sim = Simulation(config: MatchFactory.botMatch(seed: seed))
        sim.runHeadless(maxTime: seconds)
        return sim.state.tick
    }
}

// MARK: - ホームのバッジ

enum HomeBadges {
    static func isExpired(_ mail: MailItem, now: Date) -> Bool {
        if let e = mail.expiresAt { return e <= now }
        return false
    }

    static func unreadMail(_ p: Profile, now: Date) -> Int {
        p.mail.filter { !$0.read && !isExpired($0, now: now) }.count
    }

    static func claimableMail(_ p: Profile, now: Date) -> Int {
        p.mail.filter { !$0.claimed && !$0.attachments.isEmpty && !isExpired($0, now: now) }.count
    }

    static func unreadNotices(_ p: Profile) -> Int {
        LiveOpsService.notices.filter { !p.readNoticeIDs.contains($0.id) }.count
    }

    /// 受け取り可能なミッション数（デイリー + ウィークリー）。
    static func claimableMissions(_ p: Profile) -> Int {
        let defs = LiveOpsService.dailyMissions(profile: p) + LiveOpsService.weeklyMissions(profile: p)
        let progress = p.missions.daily + p.missions.weekly
        return defs.filter { def in
            guard let prog = progress.first(where: { $0.id == def.id }) else { return false }
            return !prog.claimed && prog.progress >= def.target
        }.count
    }

    static func claimableAchievements(_ p: Profile) -> Int {
        LiveOpsService.achievements.filter { def in
            guard let prog = p.achievements[def.id] else { return false }
            return !prog.claimed && (prog.unlockedAt != nil || prog.progress >= def.target)
        }.count
    }

    static func claimableRankRewards(_ p: Profile) -> Int {
        RankTier.allCases.filter { t in
            t <= p.rank.highestTier && !p.rank.claimedTierRewards.contains(t.rawValue) && !RankService.tierRewards(t).isEmpty
        }.count
    }

    static func firstWinAvailable(_ p: Profile, now: Date) -> Bool {
        p.lastFirstWinDayKey != LiveOpsService.dayKey(now)
    }
}

// MARK: - ランク戦ドラフト

struct DraftTurn: Equatable {
    enum Action: Equatable { case ban, pick }

    let team: Team
    let action: Action
    /// 人間プレイヤーが操作する手番か。
    let isPlayer: Bool
    /// ピック枠の表示名（"B1" / "R3"）。BAN は空。
    let slotLabel: String
}

struct DraftPick: Equatable, Identifiable {
    var id: String { heroID }
    var heroID: String
    var position: LanePosition
    var isPlayer: Bool
}

/// BAN 2 × 2 → スネークピック（B1 R1 R2 B2 B3 R3 R4 B4 B5 R5）。プレイヤーは B1。
/// AI の選択は SplitMix64 で決定的（同じシード・同じ入力なら同じ結果）。
struct DraftEngine: Equatable {
    static let bansPerTeam = 2

    static let turns: [DraftTurn] = {
        var t: [DraftTurn] = [
            DraftTurn(team: .blue, action: .ban, isPlayer: true, slotLabel: ""),
            DraftTurn(team: .red, action: .ban, isPlayer: false, slotLabel: ""),
            DraftTurn(team: .blue, action: .ban, isPlayer: false, slotLabel: ""),
            DraftTurn(team: .red, action: .ban, isPlayer: false, slotLabel: ""),
        ]
        let snake: [(Team, Int)] = [(.blue, 1), (.red, 1), (.red, 2), (.blue, 2), (.blue, 3),
                                    (.red, 3), (.red, 4), (.blue, 4), (.blue, 5), (.red, 5)]
        for (team, n) in snake {
            t.append(DraftTurn(team: team, action: .pick, isPlayer: team == .blue && n == 1,
                               slotLabel: (team == .blue ? "B" : "R") + "\(n)"))
        }
        return t
    }()

    /// 全ヒーロー ID（ID 昇順）。
    let heroIDs: [String]
    let ownedHeroIDs: [String]
    private let roles: [Role]
    private(set) var rng: SplitMix64
    private(set) var turnIndex = 0
    private(set) var blueBans: [String?] = []
    private(set) var redBans: [String?] = []
    private(set) var bluePicks: [DraftPick] = []
    private(set) var redPicks: [DraftPick] = []

    init(seed: UInt64, ownedHeroIDs: [String], master: MasterData = .shared) {
        heroIDs = master.heroes.map(\.heroID)
        roles = master.heroes.map(\.role)
        self.ownedHeroIDs = ownedHeroIDs
        rng = SplitMix64(seed: seed ^ 0xD8AF_7B4E_11C3_9A05)
    }

    var currentTurn: DraftTurn? { turnIndex < Self.turns.count ? Self.turns[turnIndex] : nil }
    var isComplete: Bool { turnIndex >= Self.turns.count }
    var bannedHeroIDs: [String] { (blueBans + redBans).compactMap { $0 } }
    var pickedHeroIDs: [String] { (bluePicks + redPicks).map(\.heroID) }
    var playerPick: DraftPick? { bluePicks.first { $0.isPlayer } }

    func bans(for team: Team) -> [String?] { team == .blue ? blueBans : redBans }
    func picks(for team: Team) -> [DraftPick] { team == .blue ? bluePicks : redPicks }

    func role(of heroID: String) -> Role? {
        guard let i = heroIDs.firstIndex(of: heroID) else { return nil }
        return roles[i]
    }

    func isTaken(_ heroID: String) -> Bool {
        bannedHeroIDs.contains(heroID) || pickedHeroIDs.contains(heroID)
    }

    /// プレイヤーがまだ選べる所持ヒーロー（ID 昇順）。
    var playerOwnedAvailable: [String] {
        heroIDs.filter { ownedHeroIDs.contains($0) && !isTaken($0) }
    }

    /// プレイヤーがピックできるヒーローか。所持ヒーローが 1 体も残っていない場合（復元データの欠損など）は
    /// ドラフトが止まらないよう、空いている全ヒーローを選べるようにする。
    func isPlayerPickable(_ heroID: String) -> Bool {
        ownedHeroIDs.contains(heroID) || playerOwnedAvailable.isEmpty
    }

    /// BAN するとプレイヤーのピック候補（所持ヒーロー）が無くなるか。ピック前の BAN でのみ守る。
    func banWouldStrandPlayer(_ heroID: String) -> Bool {
        playerPick == nil && ownedHeroIDs.contains(heroID) && playerOwnedAvailable.count <= 1
    }

    /// プレイヤーの手番で、このヒーローを選べるか（ピックは所持ヒーローのみ）。
    func canPlayerSelect(_ heroID: String) -> Bool {
        guard let t = currentTurn, t.isPlayer, heroIDs.contains(heroID), !isTaken(heroID) else { return false }
        return t.action == .ban ? !banWouldStrandPlayer(heroID) : isPlayerPickable(heroID)
    }

    func openPositions(for team: Team) -> [LanePosition] {
        let taken = picks(for: team).map(\.position)
        return LanePosition.allCases.filter { !taken.contains($0) }
    }

    /// ロールに最も合う空きポジション。
    func bestOpenPosition(for role: Role, team: Team) -> LanePosition {
        let open = openPositions(for: team)
        let preferred = MatchFactory.defaultPosition(for: role)
        if open.contains(preferred) { return preferred }
        if let fit = open.first(where: { MatchFactory.preferredRoles(for: $0).contains(role) }) { return fit }
        return open.first ?? preferred
    }

    /// 現在の手番を確定する。BAN は nil でスキップ（時間切れ）。成功で true。
    @discardableResult
    mutating func commit(_ heroID: String?) -> Bool {
        guard let turn = currentTurn else { return false }
        switch turn.action {
        case .ban:
            if let id = heroID {
                guard heroIDs.contains(id), !isTaken(id), !banWouldStrandPlayer(id) else { return false }
            }
            if turn.team == .blue { blueBans.append(heroID) } else { redBans.append(heroID) }
        case .pick:
            guard let id = heroID, let role = role(of: id), !isTaken(id) else { return false }
            if turn.isPlayer && !isPlayerPickable(id) { return false }
            let pick = DraftPick(heroID: id, position: bestOpenPosition(for: role, team: turn.team), isPlayer: turn.isPlayer)
            if turn.team == .blue { bluePicks.append(pick) } else { redPicks.append(pick) }
        }
        turnIndex += 1
        return true
    }

    /// AI 手番の選択（プレイヤー手番・完了後は nil）。
    mutating func aiChoice() -> String? {
        guard let turn = currentTurn, !turn.isPlayer else { return nil }
        let available = heroIDs.filter { !isTaken($0) }
        switch turn.action {
        case .ban:
            return rng.pick(available.filter { !banWouldStrandPlayer($0) })
        case .pick:
            let target = openPositions(for: turn.team).first ?? .mid
            for role in MatchFactory.preferredRoles(for: target) {
                let pool = available.filter { self.role(of: $0) == role }
                if let h = rng.pick(pool) { return h }
            }
            return rng.pick(available)
        }
    }

    /// プレイヤーの持ち時間切れ時の自動選択。BAN はスキップ（nil）、ピックは希望順 → 所持の先頭。
    func autoChoiceForPlayer(preferred: [String]) -> String? {
        guard let turn = currentTurn, turn.isPlayer else { return nil }
        if turn.action == .ban { return nil }
        if let h = preferred.first(where: { canPlayerSelect($0) }) { return h }
        return heroIDs.first { canPlayerSelect($0) }
    }

    /// ドラフト後のポジション変更（同じ枠の味方と入れ替え）。
    mutating func setPlayerPosition(_ position: LanePosition) {
        guard let pi = bluePicks.firstIndex(where: { $0.isPlayer }) else { return }
        let old = bluePicks[pi].position
        guard old != position else { return }
        if let other = bluePicks.firstIndex(where: { $0.position == position }) {
            bluePicks[other].position = old
        }
        bluePicks[pi].position = position
    }

    func heroID(team: Team, position: LanePosition) -> String? {
        picks(for: team).first { $0.position == position }?.heroID
    }

    /// MatchFactory が作った構成の AI 枠を、ドラフトの結果で置き換える。
    func apply(to config: inout MatchConfig, master: MasterData = .shared) {
        for i in config.players.indices where config.players[i].controller == .bot {
            let slot = config.players[i]
            guard let h = heroID(team: slot.team, position: slot.position) else { continue }
            config.players[i].heroID = h
            config.players[i].displayName = "\(master.hero(h)?.codeName ?? h)_AI"
            config.players[i].skinID = nil
        }
    }
}

// MARK: - バックアップの復元（UI005）

/// 復元データと現在のデータを統合する。
/// 端末で申告した年齢区分・課金の記録は巻き戻さない（古いバックアップで当月の課金額を戻したり、
/// 年齢区分を差し替えたりして、年齢別の月間購入上限（DESIGN §12）を回避できないようにする）。
enum BackupRestore {
    static func merged(imported: Profile, current: Profile) -> Profile {
        var p = imported

        // 年齢区分はこの端末で最後に申告したもの
        p.ageBracket = current.ageBracket ?? imported.ageBracket

        // 課金台帳は Transaction.id で和集合（どちらかで取り消し済みなら取り消し扱い）
        var ledger = imported.purchaseLedger
        for record in current.purchaseLedger {
            if let i = ledger.firstIndex(where: { $0.transactionID == record.transactionID }) {
                ledger[i].revoked = ledger[i].revoked || record.revoked
            } else {
                ledger.append(record)
            }
        }
        p.purchaseLedger = ledger.sorted { $0.date == $1.date ? $0.transactionID < $1.transactionID : $0.date < $1.date }

        // 月ごとの課金額は大きい方（上限判定が緩くならない側）
        for month in current.monthlySpendJPY.keys.sorted() {
            p.monthlySpendJPY[month] = max(p.monthlySpendJPY[month] ?? 0, current.monthlySpendJPY[month] ?? 0)
        }

        // 同意済みの規約・完了済みのオンボーディングは戻さない。初回準備は端末ごとの処理なので現在の値
        p.acceptedTermsVersion = max(imported.acceptedTermsVersion, current.acceptedTermsVersion)
        p.onboardingCompleted = imported.onboardingCompleted || current.onboardingCompleted
        p.tutorialCompleted = imported.tutorialCompleted || current.tutorialCompleted
        p.firstResourcePrepared = current.firstResourcePrepared
        if PlayerNameRules.validate(p.displayName) != nil, PlayerNameRules.validate(current.displayName) == nil {
            p.displayName = current.displayName
        }
        return p
    }
}

// MARK: - 対戦フローの入口指定

/// 対戦フローを特定のモードから開く（リザルトの「もう一度」・ランク画面から）。
@MainActor
enum MatchFlowIntent {
    enum Entry: Equatable {
        case standard(Difficulty)
        case ranked
    }

    static var pending: Entry?

    /// 他の全画面表示が閉じ終わるのを待ってから対戦フローを開く。
    static func present(_ entry: Entry?, app: AppModel, delay: Duration = .zero) {
        pending = entry
        if delay == .zero {
            app.router.isMatchFlowPresented = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard app.activeBattle == nil else { return }
            app.router.isMatchFlowPresented = true
        }
    }

    static func consume() -> Entry? {
        defer { pending = nil }
        return pending
    }
}

// MARK: - MVP スコアの内訳（DESIGN §11）

struct MVPBreakdown: Equatable {
    struct Line: Equatable {
        var label: String
        var detail: String
        var value: Double
    }

    var lines: [Line]
    var total: Double { lines.reduce(0) { $0 + $1.value } }

    static func make(_ p: PlayerSummary, won: Bool) -> MVPBreakdown {
        let s = p.score
        return MVPBreakdown(lines: [
            Line(label: L("キル", "Kills"), detail: "\(s.kills) × 3", value: Double(s.kills) * 3),
            Line(label: L("アシスト", "Assists"), detail: "\(s.assists) × 2", value: Double(s.assists) * 2),
            Line(label: L("デス", "Deaths"), detail: "\(s.deaths) × −1.5", value: -Double(s.deaths) * 1.5),
            Line(label: L("与ダメージ", "Hero damage"), detail: "\(Int(s.damageToHeroes)) ÷ 1000", value: s.damageToHeroes / 1000),
            Line(label: L("タワーダメージ", "Tower damage"), detail: "\(Int(s.towerDamage)) ÷ 1500", value: s.towerDamage / 1500),
            Line(label: L("回復量", "Healing"), detail: "\(Int(s.healingDone)) ÷ 2000", value: s.healingDone / 2000),
            Line(label: "CS", detail: "\(s.creepScore) ÷ 20", value: Double(s.creepScore) / 20),
            Line(label: L("勝利ボーナス", "Victory bonus"), detail: won ? "+3" : "—", value: won ? 3 : 0),
        ])
    }

    /// 次の試合に向けた助言（数値から最大 3 件）。
    static func advice(_ p: PlayerSummary, durationMinutes: Double) -> [String] {
        let s = p.score
        var out: [String] = []
        let minutes = max(1, durationMinutes)
        if s.deaths > s.kills + s.assists || s.deaths >= 6 {
            out.append(L("デスが多めです。HP が減ったら早めに帰還し、タワーの射程を意識しましょう。",
                         "You died often. Recall earlier when low and respect tower range."))
        }
        if p.position != .support && Double(s.creepScore) / minutes < 4 {
            out.append(L("ミニオンのラストヒットで CS を伸ばすとゴールドが増え、評価も上がります。",
                         "Last-hit more minions to raise CS, gold and your grade."))
        }
        if s.towerDamage < 1500 {
            out.append(L("味方ミニオンと一緒にタワーを攻めると、タワーダメージが評価に加算されます。",
                         "Push towers with your minion wave — tower damage counts toward your score."))
        }
        if s.damageToHeroes / minutes < 600 && out.count < 3 {
            out.append(L("集団戦ではスキルを積極的に当てて、ヒーローへのダメージを伸ばしましょう。",
                         "Land more skills in team fights to raise your hero damage."))
        }
        if out.isEmpty {
            out.append(L("素晴らしい試合でした。この調子で上位の難易度にも挑戦してみましょう。",
                         "Great game! Try a higher difficulty next."))
        }
        return Array(out.prefix(3))
    }
}

// MARK: - 通報・不具合報告（UI034）

enum SupportReportCategory: String, CaseIterable, Identifiable {
    case bug, aiBehavior, balance, display, performance, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return L("不具合", "Bug")
        case .aiBehavior: return L("AI の挙動", "AI behavior")
        case .balance: return L("バランス", "Balance")
        case .display: return L("表示・操作", "Display / controls")
        case .performance: return L("動作の重さ", "Performance")
        case .other: return L("その他", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .bug: return "ant.fill"
        case .aiBehavior: return "cpu"
        case .balance: return "scalemass.fill"
        case .display: return "rectangle.on.rectangle"
        case .performance: return "speedometer"
        case .other: return "ellipsis.bubble.fill"
        }
    }
}

enum SupportMail {
    /// RFC 6068 の mailto 用に厳密にパーセントエンコードする（英数字と -._~ 以外すべて）。
    static func encode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func url(to address: String, subject: String, body: String) -> URL? {
        URL(string: "mailto:\(address)?subject=\(encode(subject))&body=\(encode(body))")
    }

    static func subject(category: SupportReportCategory) -> String {
        "[VELSTRIA] \(L("報告", "Report")): \(category.title)"
    }

    /// 端末識別子（例: iPhone17,1）。
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let id = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(bitPattern: v)))) }
        }
        return id.isEmpty ? "unknown" : id
    }

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// 本文（試合情報付き）。個人を特定する情報（名前・プレイヤー ID）は含めない。
    static func body(category: SupportReportCategory, message: String, summary: MatchSummary,
                     launch: BattleLaunch, systemVersion: String) -> String {
        var lines: [String] = []
        lines.append(L("■ 内容", "■ Details"))
        lines.append(message.isEmpty ? L("（未記入）", "(empty)") : message)
        lines.append("")
        lines.append(L("■ 試合情報", "■ Match info"))
        lines.append("\(L("種別", "Category")): \(category.title)")
        lines.append("\(L("モード", "Mode")): \(FlowText.mode(summary.mode))\(launch.replay != nil ? " (" + L("リプレイ", "Replay") + ")" : "")")
        lines.append("Seed: \(summary.seed)")
        lines.append("\(L("試合時間", "Duration")): \(FlowText.duration(summary.duration))")
        lines.append("\(L("終了理由", "End reason")): \(FlowText.endReason(summary.endReason))")
        if let w = summary.winner { lines.append("\(L("勝利チーム", "Winner")): \(FlowText.team(w))") }
        if let h = summary.humanPlayer {
            lines.append("\(L("使用ヒーロー", "Hero")): \(h.heroID) / \(FlowText.position(h.position))")
            lines.append("K/D/A: \(FlowText.kda(h.score.kills, h.score.deaths, h.score.assists))")
        }
        if let enemy = launch.config.players.first(where: { $0.controller == .bot && $0.team != (summary.humanTeam ?? .blue) }) {
            lines.append("AI: \(FlowText.difficulty(enemy.botDifficulty))")
        }
        lines.append("Sim v\(launch.config.simVersion)")
        lines.append("")
        lines.append(L("■ 環境", "■ Environment"))
        lines.append("App: \(appVersion)")
        lines.append("iOS: \(systemVersion)")
        lines.append("Device: \(deviceModel)")
        return lines.joined(separator: "\n")
    }
}
