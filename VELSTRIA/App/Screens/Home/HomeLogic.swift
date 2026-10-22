import SwiftUI
import VelstriaCore

// 担当: home-chrome。ホーム画面の純粋ロジック（ロビーの配置・ドロワーの項目・表示用の書式）。
// ビューには依存しない。テストは AppTests/HomeScreenTests.swift。

// MARK: - 配置

/// ホームのロビー（採用案 Celestial Saber。docs/design/CELESTIAL_HOME.md）の配置。原画 1774 × 887 を 1024 × 512 の板に
/// 正規化し、セーフエリアの内側に縦横同じ倍率で収める（余った所はぼかした背景で埋める）。
///
/// 対応端末は iPhone の横画面のみ: SE 第 3 世代（667×375、インセットなし）〜 17 Pro Max（956×440、左右 62・下 21）。
/// 左右のインセットで Dynamic Island と角丸を、下のインセットでホームインジケータを避ける。
struct HomeLayout: Equatable {
    /// 板の大きさ（部品はこの座標で置く。HomeLobbySlot）。
    static let board = CGSize(width: 1024, height: 512)

    /// 画面全体（セーフエリアを含む）。
    let size: CGSize
    let safeArea: EdgeInsets
    /// 板を置ける領域（セーフエリアの内側）。
    let safeRect: CGRect
    /// 板の倍率（縦横同じ）。
    let scale: CGFloat
    /// 画面上の板の位置（safeRect の中央）。
    let boardRect: CGRect
    /// メニュードロワーの中身を置ける右端と、ドロワーの幅（右のセーフエリアを含む）。
    let contentMaxX: CGFloat
    let drawerWidth: CGFloat

    init(size: CGSize, safeArea: EdgeInsets) {
        self.size = size
        self.safeArea = safeArea
        safeRect = CGRect(x: safeArea.leading, y: safeArea.top,
                          width: max(1, size.width - safeArea.leading - safeArea.trailing),
                          height: max(1, size.height - safeArea.top - safeArea.bottom))
        scale = min(safeRect.width / Self.board.width, safeRect.height / Self.board.height)
        let width = Self.board.width * scale
        let height = Self.board.height * scale
        boardRect = CGRect(x: safeRect.midX - width / 2, y: safeRect.midY - height / 2, width: width, height: height)
        contentMaxX = size.width - max(safeArea.trailing, 12)
        drawerWidth = min(380, max(316, (safeRect.width * 0.5).rounded())) + (size.width - contentMaxX)
    }

    /// 板の座標の矩形を画面の座標へ。
    func screenRect(_ r: CGRect) -> CGRect {
        CGRect(x: boardRect.minX + r.minX * scale, y: boardRect.minY + r.minY * scale,
               width: r.width * scale, height: r.height * scale)
    }
}

/// ロビーの部品の位置（板の座標。採用案の原画から測った値）。ビューはこの矩形に置き、テストは全端末のセーフエリアに収まることを確かめる。
enum HomeLobbySlot {
    static let profile = CGRect(x: 26, y: 27, width: 168, height: 49)
    /// 右上の列（コイン・ジェム・メール・フレンド欄の開閉・設定・≡）。
    static let headerIcons = CGRect(x: 615, y: 25, width: 382, height: 38)
    /// 中央のキービジュアル（押すとヒーロー一覧）。
    static let keyVisual = CGRect(x: 228, y: 75, width: 525, height: 330)
    static let events = CGRect(x: 24, y: 98, width: 198, height: 91)
    static let starPass = CGRect(x: 24, y: 198, width: 198, height: 91)
    /// 左の列（ストア・ミッション・イベント）。
    static let rail = CGRect(x: 28, y: 306, width: 192, height: 49)
    static let friends = CGRect(x: 773, y: 79, width: 226, height: 274)
    static let footerBand = CGRect(x: 10, y: 419, width: 1004, height: 81)
    /// フッターのタブ（戦闘準備・ヒーロー・コレクション・バッグ）。
    static let footerTabs = CGRect(x: 17, y: 420, width: 484, height: 70)
    static let emblems = CGRect(x: 502, y: 427, width: 27, height: 60)
    static let rank = CGRect(x: 535, y: 424, width: 199, height: 66)
    static let play = CGRect(x: 746, y: 414, width: 263, height: 69)

    /// 押せる部品の一覧（テスト用）。
    static let all: [(name: String, rect: CGRect)] = [
        ("profile", profile), ("headerIcons", headerIcons), ("keyVisual", keyVisual), ("events", events),
        ("starPass", starPass), ("rail", rail), ("friends", friends), ("footerTabs", footerTabs),
        ("emblems", emblems), ("rank", rank), ("play", play),
    ]
}

// MARK: - メニュードロワー

/// ドロワーの項目（定義順 = 表示順）。識別子は `home_menu_<遷移先の名前>`。
/// ロビー（採用案）に入口の無い画面だけを置く（同じ入口を二つ作らない）: 実績・戦績はプロフィール、サポートは設定、
/// コレクション（エモート）は下段、練習場・チュートリアルはモード選択の「VS AI & カスタム」、パッチノートはお知らせの中。
enum HomeMenuItem: String, CaseIterable, Identifiable {
    case notices, ranking, spectateSetup, spells

    var id: String { rawValue }
    var identifier: String { "home_menu_\(rawValue)" }

    var route: Route {
        switch self {
        case .notices: return .notices
        case .ranking: return .ranking
        case .spectateSetup: return .spectateSetup
        case .spells: return .spells
        }
    }

    var title: String {
        switch self {
        case .notices: return L("お知らせ", "News")
        case .ranking: return L("ランキング", "Leaderboard")
        case .spectateSetup: return L("観戦", "Spectate")
        case .spells: return L("バトルスキル", "Battle Skills")
        }
    }

    var symbol: String {
        switch self {
        case .notices: return "megaphone.fill"
        case .ranking: return "trophy.fill"
        case .spectateSetup: return "eye.fill"
        case .spells: return "bolt.fill"
        }
    }
}

// MARK: - 識別子の一覧

enum HomeIdentifiers {
    /// ロビーの固定の識別子（アイコンは home_<遷移先の名前>。左の列は home_rail_<遷移先の名前>）。
    static let fixed = [
        "home_profile", "home_currency_coin", "home_currency_gem", "home_mail", "home_friends_toggle", "home_settings", "home_menu",
        "home_heroes_visual", "home_events", "home_starPass", "home_rail_store", "home_rail_missions", "home_rail_events",
        "home_friend_find", "home_items", "home_heroes", "home_cosmetics", "home_inventory",
        "home_emblems", "home_rank", "home_play", "home_menu_close",
    ]

    /// ホーム画面が使う全ての識別子（重複が無いことをテストで確かめる）。フレンドの行は home_friend_<コード>・home_friend_invite_<コード>。
    static var all: [String] { fixed + HomeMenuItem.allCases.map(\.identifier) }
}

// MARK: - 左のカード: スターパス

/// スターパスのカードに出す進み具合（「Lv.12/30」と、今の段の中の割合）。
struct HomePassProgress: Equatable {
    let level: Int
    let fraction: Double

    init(xp: Int) {
        level = LiveOpsService.passLevel(xp: xp)
        fraction = level >= LiveOpsService.passMaxLevel
            ? 1 : Double(LiveOpsService.passXPInLevel(xp: xp)) / Double(LiveOpsService.passXPPerLevel)
    }

    var label: String { "Lv.\(level)/\(LiveOpsService.passMaxLevel)" }
}

// MARK: - フレンド欄: 状態

/// フレンドの状態（MLBB のフレンド一覧と同じ並び）。試合中・練習中は在席の情報に状態が載ってから（第3段）。
/// フレンドの状態（MLBB のフレンド一覧: オンライン・ランキングルーム中・マッチング中・試合中（「ランキング1分」）・集計中・ライブ観戦・Offline）。
enum HomeFriendStatus: Equatable {
    case offline, online, inTeam, inMatch, practicing
    /// ルーム中（モード。nil = 不明）。
    case inRoom(MatchMode?)
    case matching
    /// 試合中（モードと経過の分）。
    case playing(MatchMode?, minutes: Int)
    case tallying, spectating

    /// 色の分け方（緑 = 遊べる、橙 = マッチング・試合など、青 = 観戦、灰 = オフライン）。
    enum Tone { case available, busy, watching, offline }

    static func of(online: Bool, inMyTeam: Bool) -> HomeFriendStatus {
        guard online else { return .offline }
        return inMyTeam ? .inTeam : .online
    }

    /// 在席・自分のチームか・フレンドが知らせてきた今の状態から。
    static func of(online: Bool, inMyTeam: Bool, activity: FriendActivity?, now: Date) -> HomeFriendStatus {
        guard online else { return .offline }
        if inMyTeam { return .inTeam }
        guard let a = activity else { return .online }
        let mode = FriendActivityMode.mode(a.m)
        switch a.kind {
        case .online: return .online
        case .room: return .inRoom(mode)
        case .matching: return .matching
        case .match:
            let minutes = a.at.map { max(0, Int(now.timeIntervalSince1970 - $0 / 1000) / 60) } ?? 0
            return .playing(mode, minutes: minutes)
        case .tally: return .tallying
        case .watch: return .spectating
        case .practice: return .practicing
        }
    }

    var title: String {
        switch self {
        case .offline: return "Offline"
        case .online: return L("オンライン", "Online")
        case .inTeam: return L("チーム中", "In team")
        case .inMatch: return L("試合中", "In match")
        case .practicing: return L("練習中", "Practicing")
        case .inRoom(let m): return m.map { L("\(FlowText.mode($0))ルーム中", "In \(FlowText.mode($0)) room") } ?? L("ルーム中", "In a room")
        case .matching: return L("マッチング中", "Matchmaking")
        case .playing(let m, let minutes):
            guard let m else { return L("試合中", "In match") }
            return L("\(FlowText.mode(m))\(max(1, minutes))分", "\(FlowText.mode(m)) \(max(1, minutes))m")
        case .tallying: return L("集計中", "Tallying")
        case .spectating: return L("ライブ観戦", "Watching")
        }
    }

    var tone: Tone {
        switch self {
        case .offline: return .offline
        case .online, .inTeam: return .available
        case .spectating: return .watching
        default: return .busy
        }
    }

    /// 印（オンラインは緑の ✓、観戦は青い ▶）。
    var symbol: String {
        switch tone {
        case .available: return "checkmark.circle.fill"
        case .busy: return "circle.fill"
        case .watching: return "play.circle.fill"
        case .offline: return "circle"
        }
    }

    /// 緑の印にする（遊べる状態か、遊んでいる）。
    var isActive: Bool { self != .offline }

    /// 招待できるか（オンラインで、まだ自分のチームにいない）。
    var canInvite: Bool { self == .online }
}

/// 状態で知らせるモードの名前（relay は英小文字だけを通す）。
enum FriendActivityMode {
    private static let table: [(MatchMode, String)] = [
        (.standard, "classic"), (.ranked, "ranked"), (.brawl, "brawl"), (.custom, "custom"), (.magicChess, "chess"),
        (.online, "online"), (.practice, "practice"), (.tutorial, "tutorial"), (.spectate, "spectate"),
    ]

    static func code(_ m: MatchMode) -> String { table.first { $0.0 == m }?.1 ?? "classic" }
    static func mode(_ code: String?) -> MatchMode? { table.first { $0.1 == code }?.0 }
}

// MARK: - 書式

enum HomeFormat {
    /// 通貨の表示。桁区切りつきで、100 万以上は「1.2M」のように丸める。
    /// compact（小さい画面）では 10 万以上を「123K」にして幅を抑える。
    static func currency(_ amount: Int, compact: Bool = false) -> String {
        let value = max(0, amount)
        if value >= 1_000_000_000 { return abbreviated(value, unit: 1_000_000_000, suffix: "B") }
        if value >= 1_000_000 { return abbreviated(value, unit: 1_000_000, suffix: "M") }
        if compact && value >= 100_000 { return "\(value / 1000)K" }
        return grouped(value)
    }

    /// 切り捨てで小数 1 桁（100 以上は整数）。実際より多く見せない。
    private static func abbreviated(_ value: Int, unit: Int, suffix: String) -> String {
        let whole = value / unit
        if whole >= 100 { return "\(whole)\(suffix)" }
        let tenth = (value % unit) / (unit / 10)
        return tenth == 0 ? "\(whole)\(suffix)" : "\(whole).\(tenth)\(suffix)"
    }

    /// 3 桁ごとにカンマ（ロケールに依らない）。
    private static func grouped(_ value: Int) -> String {
        var digits = String(value)
        var out = ""
        while digits.count > 3 {
            out = "," + digits.suffix(3) + out
            digits.removeLast(3)
        }
        return digits + out
    }

    /// イベントの残り時間（分まで。秒は出さない）。
    static func remaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int((interval.isFinite ? interval : 0).rounded(.down)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return L("残り \(days)日 \(hours)時間", "\(days)d \(hours)h left") }
        if hours > 0 { return L("残り \(hours)時間 \(minutes)分", "\(hours)h \(minutes)m left") }
        return L("残り \(max(1, minutes))分", "\(max(1, minutes))m left")
    }
}
