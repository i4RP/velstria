import SwiftUI
import VelstriaCore

// 担当: home-chrome。ホーム画面の純粋ロジック（寸法計算・各部の項目一覧・ショーケースの巡回・表示用の書式）。
// ビューには依存しない。テストは AppTests/HomeScreenTests.swift。

// MARK: - 寸法

/// ホーム画面の配置。画面サイズ（セーフエリアを含む全体）とセーフエリアから、各部の矩形を全画面座標で決める。
///
/// 対応端末は iPhone の横画面のみ: SE 第 3 世代（667×375、インセットなし）〜 17 Pro Max（956×440、左右 62・下 21）。
/// 帯（ヘッダー・フッター）は画面端まで、中身は `contentMinX...contentMaxX` の内側に置く。
struct HomeMetrics: Equatable {
    /// 各列の最小幅（これを下回る端末は対応外）。
    static let minLeftRailWidth: CGFloat = 140
    static let minRightRailWidth: CGFloat = 188
    static let minCenterWidth: CGFloat = 240
    /// 当たり判定の最小サイズ。
    static let minTapSize: CGFloat = 44

    /// 画面全体（セーフエリアを含む）。
    let size: CGSize
    let safeArea: EdgeInsets

    /// SE 級の小さい画面（文字と余白を詰める）。
    let isCompact: Bool
    /// 中身を置ける左右の端。
    let contentMinX: CGFloat
    let contentMaxX: CGFloat
    /// 縦方向の基本の間隔（帯とレールの間、レール内の項目間）。
    let spacing: CGFloat

    // 帯
    let headerRect: CGRect
    let footerRect: CGRect
    /// フッターのタブ帯の高さ（下端の余白を除く）。
    let footerBarHeight: CGFloat
    /// ヘッダー中央のロゴを出すか（幅に余裕がある端末だけ）。
    let showsLogo: Bool
    let logoHeight: CGFloat

    // 左レール
    let leftRailRect: CGRect
    let bannerHeight: CGFloat
    let listItemHeight: CGFloat

    // 右レール
    let rightRailRect: CGRect
    /// モードカードのスクロール領域の高さ。
    let modeListHeight: CGFloat
    /// 一度に見えるモードカードの枚数（カードが 44pt 以上になる最大の整数。続きは下向きのヒントで示す）。
    let modeVisibleCount: Int
    /// カード 1 枚分の送り（カード + 間隔）。
    let modeSlotHeight: CGFloat
    let modeCardSpacing: CGFloat
    let socialRowHeight: CGFloat
    /// 折りたたみ取っ手（見た目の矩形。当たり判定は左右へ広げて 44pt）。
    let handleRect: CGRect

    // フッター
    let tabsRect: CGRect
    let startRect: CGRect
    /// 初勝利ボーナスのチップ（START の真上）。
    let firstWinChipRect: CGRect

    // 中央
    /// ショーケースの操作部品を置ける領域。クロームと重ならない（右レールを畳んでも変えない。畳むと戦場が見えるだけ）。
    let centerRect: CGRect

    // ドロワー
    /// メニュードロワーの幅（右のセーフエリアを含む）。
    let drawerWidth: CGFloat

    init(size: CGSize, safeArea: EdgeInsets) {
        self.size = size
        self.safeArea = safeArea
        let w = size.width
        let h = size.height
        // 高さ 375（SE）→ 440（Pro Max）を 0→1 に写して、帯やボタンの大きさを決める
        let k = min(1, max(0, (h - 375) / 65))
        func scaled(_ small: CGFloat, _ large: CGFloat) -> CGFloat { (small + (large - small) * k).rounded() }

        // ノッチ端末はセーフエリアをそのまま余白にし、無い端末は 12pt 空ける
        contentMinX = max(safeArea.leading, 12)
        contentMaxX = w - max(safeArea.trailing, 12)
        let contentWidth = contentMaxX - contentMinX
        isCompact = contentWidth < 700 || h < 380
        spacing = isCompact ? 5 : 6

        // 帯
        let headerHeight = scaled(46, 54)
        headerRect = CGRect(x: 0, y: 0, width: w, height: safeArea.top + headerHeight)
        footerBarHeight = scaled(46, 52)
        // ホームインジケータは隠しているので、下のセーフエリアは一部だけ空ける
        let bottomPadding: CGFloat = safeArea.bottom > 0 ? max(6, safeArea.bottom - 13) : 4
        footerRect = CGRect(x: 0, y: h - footerBarHeight - bottomPadding, width: w, height: footerBarHeight + bottomPadding)
        showsLogo = contentWidth >= 740
        logoHeight = headerHeight - 12

        let bodyTop = headerRect.maxY + spacing
        let bodyBottom = footerRect.minY - spacing

        // 列幅
        let leftWidth = min(176, max(Self.minLeftRailWidth, (contentWidth * 0.21).rounded()))
        let rightWidth = min(232, max(Self.minRightRailWidth, (contentWidth * 0.285).rounded()))
        let handleWidth: CGFloat = 18
        // 取っ手の当たり判定（左右 13pt ずつ広げる）とショーケースの矢印が重ならないための空き
        let handleClearance: CGFloat = 14
        let centerGap: CGFloat = 10

        // 左レール
        leftRailRect = CGRect(x: contentMinX, y: bodyTop, width: leftWidth, height: bodyBottom - bodyTop)
        listItemHeight = scaled(Self.minTapSize, 50)
        bannerHeight = min(80, max(48, ((leftRailRect.height - 3 * listItemHeight - 4 * spacing) / 2).rounded(.down)))

        // START（右下。フッターより背が高く、上へはみ出す）と初勝利チップ
        let startSize = CGSize(width: rightWidth + handleWidth, height: scaled(64, 80))
        startRect = CGRect(x: contentMaxX - startSize.width, y: h - bottomPadding - startSize.height,
                           width: startSize.width, height: startSize.height)
        let chipHeight: CGFloat = 16
        firstWinChipRect = CGRect(x: startRect.minX, y: startRect.minY - 3 - chipHeight, width: startRect.width, height: chipHeight)

        // 右レール（モードカード + ソーシャル行）。チップの上まで
        let railBottom = firstWinChipRect.minY - 4
        rightRailRect = CGRect(x: contentMaxX - rightWidth, y: bodyTop, width: rightWidth, height: railBottom - bodyTop)
        socialRowHeight = Self.minTapSize
        modeListHeight = rightRailRect.height - socialRowHeight - spacing
        modeCardSpacing = 4
        modeVisibleCount = max(2, Int((modeListHeight / (Self.minTapSize + modeCardSpacing)).rounded(.down)))
        modeSlotHeight = modeListHeight / CGFloat(modeVisibleCount)
        let handleHeight: CGFloat = 60
        handleRect = CGRect(x: rightRailRect.minX - handleWidth, y: bodyTop + (modeListHeight - handleHeight) / 2,
                            width: handleWidth, height: handleHeight)

        // フッターのタブ（START の左まで）
        tabsRect = CGRect(x: contentMinX, y: footerRect.minY, width: startRect.minX - centerGap - contentMinX, height: footerBarHeight)

        // 中央
        let centerMinX = leftRailRect.maxX + centerGap
        centerRect = CGRect(x: centerMinX, y: bodyTop,
                            width: handleRect.minX - handleClearance - centerMinX, height: bodyBottom - bodyTop)

        drawerWidth = min(380, max(316, (contentWidth * 0.5).rounded())) + (w - contentMaxX)
    }

    /// 右レールを畳んだときに、レール本体（カードとソーシャル行）を右へ退かす量（画面の外まで）。
    var railCollapseOffset: CGFloat { size.width - rightRailRect.minX }

    /// 右レールを畳んだときに取っ手を右へ寄せる量（中身の右端に残す）。
    var handleCollapseOffset: CGFloat { contentMaxX - handleRect.maxX }

    /// フッターのタブ 1 つの幅。
    var tabWidth: CGFloat { tabsRect.width / CGFloat(HomeTab.allCases.count) }
}

// MARK: - 操作

/// ホームのボタンが起こす遷移。
enum HomeAction: Equatable {
    /// 対戦フローを開く（nil = モード選択から）。
    case match(MatchFlowIntent.Entry?)
    case push(Route)
}

// MARK: - 右レール: モード

/// 右レールのモードカード（定義順 = 表示順）。
enum HomeMode: String, CaseIterable, Identifiable {
    case ranked, classic, brawl, arcade, rising, custom, magicChess

    var id: String { rawValue }
    var identifier: String { "home_mode_\(rawValue)" }

    var title: String {
        switch self {
        case .ranked: return L("ランク戦", "Ranked")
        case .classic: return L("クラシック", "Classic")
        case .brawl: return L("乱闘", "Brawl")
        case .arcade: return L("アーケード", "Arcade")
        case .rising: return L("ライジング", "Rising")
        case .custom: return L("AI対戦 / カスタム", "AI & Custom")
        case .magicChess: return L("オートバトラー", "Auto Battler")
        }
    }

    var symbol: String {
        switch self {
        case .ranked: return "crown.fill"
        case .classic: return "flag.2.crossed.fill"
        case .brawl: return "burst.fill"
        case .arcade: return "gamecontroller.fill"
        case .rising: return "chart.line.uptrend.xyaxis"
        case .custom: return "slider.horizontal.3"
        case .magicChess: return "square.grid.3x3.fill"
        }
    }

    /// 対戦フローを直接開くモードか（それ以外は各モードの画面へ進む）。
    var startsMatch: Bool {
        switch self {
        case .ranked, .classic, .brawl: return true
        case .arcade, .rising, .custom, .magicChess: return false
        }
    }

    func action(difficulty: Difficulty) -> HomeAction {
        switch self {
        case .ranked: return .match(.ranked)
        case .classic: return .match(.standard(difficulty))
        case .brawl: return .match(.brawl(difficulty))
        case .arcade: return .push(.arcade)
        case .rising: return .push(.rising)
        case .custom: return .push(.customSetup)
        case .magicChess: return .push(.magicChess)
        }
    }

    /// カードの補足（現在の状況を 1 行で）。
    func subtitle(profile: Profile) -> String {
        switch self {
        case .ranked:
            return RankService.isPromotionMatch(profile.rank) ? L("昇格戦に挑戦", "Promotion match") : RankService.displayName(profile.rank)
        case .classic:
            return L("5v5 · 対AI · ", "5v5 · vs AI · ") + FlowText.difficulty(profile.preferredDifficulty)
        case .brawl:
            return L("単レーン · 短期決戦", "Single lane · Fast")
        case .arcade:
            return L("変則ルールで遊ぶ", "Rule variants")
        case .rising:
            let stage = profile.rising.stageIndex
            return stage >= RisingService.stageCount
                ? L("全ステージ踏破", "All stages cleared")
                : L("ステージ \(stage + 1)/\(RisingService.stageCount)", "Stage \(stage + 1)/\(RisingService.stageCount)")
        case .custom:
            return L("構成を自由に設定", "Set your own rules")
        case .magicChess:
            if let best = profile.magicChessBestPlacement {
                return L("オートバトル · 最高 \(best) 位", "Auto battler · Best #\(best)")
            }
            return L("8人オートバトル", "8-player auto battler")
        }
    }
}

// MARK: - 右レール: ソーシャル行

enum HomeSocialLink: String, CaseIterable, Identifiable {
    case online, spectate, replays

    var id: String { rawValue }

    var identifier: String {
        switch self {
        case .online: return "home_online"
        case .spectate: return "home_spectateSetup"
        case .replays: return "home_replays"
        }
    }

    var route: Route {
        switch self {
        case .online: return .onlineLobby
        case .spectate: return .spectateSetup
        case .replays: return .replays
        }
    }

    var title: String {
        switch self {
        case .online: return L("オンライン", "Online")
        case .spectate: return L("観戦", "Spectate")
        case .replays: return L("リプレイ", "Replays")
        }
    }

    var symbol: String {
        switch self {
        case .online: return "antenna.radiowaves.left.and.right"
        case .spectate: return "eye.fill"
        case .replays: return "play.rectangle.fill"
        }
    }

    /// 表示する項目（オンライン対戦は機能フラグが真のときだけ）。
    static func visible(lanMatch: Bool = FeatureFlags.lanMatch) -> [HomeSocialLink] {
        allCases.filter { $0 != .online || lanMatch }
    }
}

// MARK: - 左レール: リスト項目

enum HomeQuickLink: String, CaseIterable, Identifiable {
    case missions, store, records

    var id: String { rawValue }
    var identifier: String { "home_\(rawValue)" }

    var route: Route {
        switch self {
        case .missions: return .missions
        case .store: return .store
        case .records: return .records
        }
    }

    var title: String {
        switch self {
        case .missions: return L("ミッション", "Missions")
        case .store: return L("ショップ", "Shop")
        case .records: return L("戦績", "Records")
        }
    }

    var symbol: String {
        switch self {
        case .missions: return "checklist"
        case .store: return "cart.fill"
        case .records: return "chart.bar.xaxis"
        }
    }

    /// 項目の補足（現在の状況を 1 行で）。
    func subtitle(profile: Profile) -> String {
        switch self {
        case .missions:
            let claimable = HomeBadges.claimableMissions(profile)
            if claimable > 0 { return L("受取可能 \(claimable)", "\(claimable) to claim") }
            let daily = LiveOpsService.dailyMissions(profile: profile)
            guard !daily.isEmpty else { return L("本日のミッション", "Today's missions") }
            let done = daily.filter { def in
                profile.missions.daily.first { $0.id == def.id }.map { $0.claimed || $0.progress >= def.target } ?? false
            }.count
            return L("デイリー \(done)/\(daily.count)", "Daily \(done)/\(daily.count)")
        case .store:
            return L("スキン・ジェム", "Skins & gems")
        case .records:
            let career = profile.career
            guard career.matches > 0 else { return L("対戦の記録", "Match history") }
            let rate = Int((Double(career.wins) / Double(career.matches) * 100).rounded())
            return L("\(career.matches)戦 · 勝率 \(rate)%", "\(career.matches) games · \(rate)% WR")
        }
    }

    /// 項目の右上に出す件数。
    func badge(profile: Profile) -> Int {
        self == .missions ? HomeBadges.claimableMissions(profile) : 0
    }
}

// MARK: - フッター: タブ

enum HomeTab: String, CaseIterable, Identifiable {
    case home, heroes, items, runes, inventory

    var id: String { rawValue }
    var identifier: String { self == .home ? "home_tab_home" : "home_\(rawValue)" }

    /// 遷移先（ホームは現在地なので nil）。
    var route: Route? {
        switch self {
        case .home: return nil
        case .heroes: return .heroes
        case .items: return .items
        case .runes: return .runes
        case .inventory: return .inventory
        }
    }

    var title: String {
        switch self {
        case .home: return L("ホーム", "HOME")
        case .heroes: return L("ヒーロー", "HEROES")
        case .items: return L("装備", "ITEMS")
        case .runes: return L("ルーン", "RUNES")
        case .inventory: return L("バッグ", "BAG")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .heroes: return "person.3.fill"
        case .items: return "shield.fill"
        case .runes: return "seal.fill"
        case .inventory: return "bag.fill"
        }
    }
}

// MARK: - メニュードロワー

/// ドロワーの項目（定義順 = 表示順）。識別子は `home_menu_<遷移先の名前>`。
enum HomeMenuItem: String, CaseIterable, Identifiable {
    case achievements, ranking, practiceSetup, tutorialMenu, spells, cosmetics
    case emotes, accountLink, support, faq, patchNotes, credits

    var id: String { rawValue }
    var identifier: String { "home_menu_\(rawValue)" }

    var route: Route {
        switch self {
        case .achievements: return .achievements
        case .ranking: return .ranking
        case .practiceSetup: return .practiceSetup
        case .tutorialMenu: return .tutorialMenu
        case .spells: return .spells
        case .cosmetics: return .cosmetics
        case .emotes: return .emotes
        case .accountLink: return .accountLink
        case .support: return .support
        case .faq: return .faq
        case .patchNotes: return .patchNotes
        case .credits: return .credits
        }
    }

    var title: String {
        switch self {
        case .achievements: return L("実績", "Achievements")
        case .ranking: return L("ランキング", "Leaderboard")
        case .practiceSetup: return L("練習場", "Practice")
        case .tutorialMenu: return L("チュートリアル", "Tutorial")
        case .spells: return L("スペル", "Spells")
        case .cosmetics: return L("コスメ", "Cosmetics")
        case .emotes: return L("エモート", "Emotes")
        case .accountLink: return L("アカウント連携", "Account Link")
        case .support: return L("サポート", "Support")
        case .faq: return "FAQ"
        case .patchNotes: return L("パッチノート", "Patch Notes")
        case .credits: return L("クレジット", "Credits")
        }
    }

    var symbol: String {
        switch self {
        case .achievements: return "trophy.fill"
        case .ranking: return "list.number"
        case .practiceSetup: return "figure.run"
        case .tutorialMenu: return "graduationcap.fill"
        case .spells: return "bolt.fill"
        case .cosmetics: return "sparkles"
        case .emotes: return "face.smiling.inverse"
        case .accountLink: return "link"
        case .support: return "lifepreserver.fill"
        case .faq: return "questionmark.circle.fill"
        case .patchNotes: return "doc.text.fill"
        case .credits: return "film.fill"
        }
    }

    /// 項目の右上に出す件数（受け取れる実績）。
    func badge(profile: Profile) -> Int {
        self == .achievements ? HomeBadges.claimableAchievements(profile) : 0
    }

    /// ドロワーを開くボタン（ヘッダーの ≡）に出す件数。
    static func totalBadge(profile: Profile) -> Int {
        allCases.reduce(0) { $0 + $1.badge(profile: profile) }
    }
}

// MARK: - 識別子の一覧

enum HomeIdentifiers {
    /// ヘッダー・レール・フッター・ショーケースの固定の識別子。
    static let fixed = [
        "home_profile", "home_rank", "home_currency", "home_mail", "home_notices", "home_settings", "home_menu",
        "home_events", "home_starPass", "home_rail_toggle", "home_play", "home_menu_close",
        "home_showcase", "home_showcase_prev", "home_showcase_next", "home_showcase_3d",
    ]

    /// ホーム画面が使う全ての識別子（重複が無いことをテストで確かめる）。
    static var all: [String] {
        fixed
            + HomeQuickLink.allCases.map(\.identifier)
            + HomeMode.allCases.map(\.identifier)
            + HomeSocialLink.allCases.map(\.identifier)
            + HomeTab.allCases.map(\.identifier)
            + HomeMenuItem.allCases.map(\.identifier)
    }
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
