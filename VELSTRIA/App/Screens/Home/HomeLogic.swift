import SwiftUI
import VelstriaCore

// 担当: home-chrome。ホーム画面の純粋ロジック（ロビーの配置・ドロワーの項目・ショーケースの巡回・表示用の書式）。
// ビューには依存しない。テストは AppTests/HomeScreenTests.swift。

// MARK: - 配置

/// ホームのロビー（HomeView の HomeReferenceLobby）の配置。参照デザインの板（1024×471.5）を
/// セーフエリアの内側に縦横同じ倍率で収め、余った所は背景で埋める。
///
/// 対応端末は iPhone の横画面のみ: SE 第 3 世代（667×375、インセットなし）〜 17 Pro Max（956×440、左右 62・下 21）。
/// 左右のインセットで Dynamic Island と角丸を、下のインセットでホームインジケータを避ける。
struct HomeLayout: Equatable {
    /// 参照デザインの板の大きさ（部品はこの座標で置く。HomeLobbySlot）。
    static let board = CGSize(width: 1024, height: 471.5)

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

    /// フッターの帯。板の外の余白まで、画面の左端と下端へ伸ばす。
    var footerBandRect: CGRect {
        let r = screenRect(HomeLobbySlot.footerBand)
        return CGRect(x: 0, y: r.minY, width: r.maxX, height: size.height - r.minY)
    }
}

/// ロビーの部品の位置（板の座標）。ビューはこの矩形に置き、テストは全端末のセーフエリアに収まることを確かめる。
enum HomeLobbySlot {
    static let profile = CGRect(x: 61, y: 10, width: 140, height: 36)
    static let support = CGRect(x: 205, y: 3, width: 38, height: 44)
    static let achievements = CGRect(x: 245, y: 3, width: 38, height: 44)
    static let menu = CGRect(x: 283, y: 3, width: 44, height: 44)
    static let currency = CGRect(x: 560, y: 12.5, width: 180, height: 25)
    /// 右上のアイコン列（ランキング・戦績・観戦・メール・設定）。
    static let headerIcons = CGRect(x: 747, y: 3, width: 190, height: 44)
    static let events = CGRect(x: 61, y: 63, width: 104, height: 38)
    static let starPass = CGRect(x: 61, y: 111, width: 104, height: 38)
    static let notices = CGRect(x: 181, y: 61, width: 38, height: 44)
    /// 左の縦の列（ストア・ミッション）。
    static let rail = CGRect(x: 57, y: 157, width: 48, height: 96)
    static let friends = CGRect(x: 825, y: 70, width: 146, height: 265)
    static let firstWin = CGRect(x: 623, y: 309, width: 195, height: 29)
    static let footerBand = CGRect(x: 0, y: 419, width: 755, height: 52.5)
    static let avatar = CGRect(x: 49, y: 411, width: 112, height: 53)
    /// フッターのタブ（戦闘準備・ヒーロー・コレクション・バッグ）。
    static let footerTabs = CGRect(x: 188, y: 420, width: 508, height: 49)
    static let emblems = CGRect(x: 698, y: 420, width: 52, height: 48)
    static let rank = CGRect(x: 751, y: 387.5, width: 56, height: 77)
    static let play = CGRect(x: 808, y: 399, width: 190, height: 66)

    /// 押せる部品の一覧（テスト用）。
    static let all: [(name: String, rect: CGRect)] = [
        ("profile", profile), ("support", support), ("achievements", achievements), ("menu", menu),
        ("currency", currency), ("headerIcons", headerIcons), ("events", events), ("starPass", starPass),
        ("notices", notices), ("rail", rail), ("friends", friends), ("firstWin", firstWin), ("avatar", avatar),
        ("footerTabs", footerTabs), ("emblems", emblems), ("rank", rank), ("play", play),
    ]
}

// MARK: - メニュードロワー

/// ドロワーの項目（定義順 = 表示順）。識別子は `home_menu_<遷移先の名前>`。
/// ロビーに入口がある画面（実績・ランキング・サポート・コレクション）と、モード選択の「VS AI & カスタム」にある
/// 練習場・チュートリアルは置かない（同じ入口を二つ作らない）。
enum HomeMenuItem: String, CaseIterable, Identifiable {
    case spells, emotes, accountLink, faq, patchNotes, credits

    var id: String { rawValue }
    var identifier: String { "home_menu_\(rawValue)" }

    var route: Route {
        switch self {
        case .spells: return .spells
        case .emotes: return .emotes
        case .accountLink: return .accountLink
        case .faq: return .faq
        case .patchNotes: return .patchNotes
        case .credits: return .credits
        }
    }

    var title: String {
        switch self {
        case .spells: return L("スペル", "Spells")
        case .emotes: return L("エモート", "Emotes")
        case .accountLink: return L("アカウント連携", "Account Link")
        case .faq: return "FAQ"
        case .patchNotes: return L("パッチノート", "Patch Notes")
        case .credits: return L("クレジット", "Credits")
        }
    }

    var symbol: String {
        switch self {
        case .spells: return "bolt.fill"
        case .emotes: return "face.smiling.inverse"
        case .accountLink: return "link"
        case .faq: return "questionmark.circle.fill"
        case .patchNotes: return "doc.text.fill"
        case .credits: return "film.fill"
        }
    }
}

// MARK: - 識別子の一覧

enum HomeIdentifiers {
    /// ロビーの固定の識別子（アイコンは home_<遷移先の名前>）。
    static let fixed = [
        "home_profile", "home_support", "home_achievements", "home_menu", "home_currency",
        "home_ranking", "home_records", "home_spectateSetup", "home_mail", "home_settings",
        "home_events", "home_starPass", "home_notices", "home_store", "home_missions",
        "home_onlineLobby", "home_friends_toggle", "home_first_win", "home_hero",
        "home_avatar", "home_items", "home_heroes", "home_cosmetics", "home_inventory",
        "home_emblems", "home_rank", "home_play", "home_menu_close",
    ]

    /// ホーム画面が使う全ての識別子（重複が無いことをテストで確かめる）。
    static var all: [String] { fixed + HomeMenuItem.allCases.map(\.identifier) }
}

// MARK: - ショーケースの巡回

/// 中央ショーケースに出すヒーローの選び方（画面内の状態だけ。プロフィールには保存しない）。
enum HomeShowcaseLogic {
    /// 巡回する順番: 所持ヒーローをマスターの並び順で。
    static func roster(owned: [String], masterOrder: [String]) -> [String] {
        let ownedSet = Set(owned)
        return masterOrder.filter(ownedSet.contains)
    }

    /// 最初に出すヒーロー: 最後に選んだヒーロー（マスターに無ければアバターのヒーロー）。
    static func initialHero(lastPicked: String?, avatar: String, isKnown: (String) -> Bool) -> String {
        if let id = lastPicked, isKnown(id) { return id }
        return avatar
    }

    /// 隣のヒーロー（step > 0 = 次、step < 0 = 前）。端では反対側へ回り込む。
    /// 現在のヒーローが巡回対象に無いとき（未所持など）は、次なら先頭・前なら末尾へ入る。巡回対象が空ならそのまま。
    static func neighbor(of current: String, in roster: [String], step: Int) -> String {
        guard !roster.isEmpty, step != 0 else { return current }
        guard let index = roster.firstIndex(of: current) else {
            return step > 0 ? roster[0] : roster[roster.count - 1]
        }
        let count = roster.count
        return roster[((index + step) % count + count) % count]
    }
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
