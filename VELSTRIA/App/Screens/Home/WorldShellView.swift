import SwiftUI
import VelstriaCore

/// 非バトル画面を載せる、常設のワールド。背景・ヘッダー・右欄は画面遷移で作り直さない。
struct WorldShellView: View {
    @Environment(AppModel.self) private var app
    var battleSession: WorldBattleSession?
    @State private var sideTab: PartySideTab = .friends
    @State private var showsMenu = HomeDebug.startsMenuOpen
    @State private var showsSetup = false

    private var inSession: Bool { battleSession != nil }
    private var isHome: Bool { app.router.path.isEmpty && !app.router.isMatchFlowPresented && !showsMenu && !showsSetup && !inSession }
    private var title: String {
        if let battleSession {
            switch battleSession.phase {
            case .loading: return L("出撃準備", "Battle preparation")
            case .battle: return L("バトル", "Battle")
            case .result: return L("試合結果", "Match results")
            }
        }
        if showsSetup { return L("プレイヤー設定", "Player setup") }
        if showsMenu { return L("メニュー", "Menu") }
        if app.router.isMatchFlowPresented { return L("バトル開始", "Start battle") }
        return app.router.path.last?.worldTitle ?? L("オンライン対戦", "Online Match")
    }

    var body: some View {
        WorldShellFrame(title: title, subtitle: isHome ? L("- パーティ", "- Party") : nil,
                        sideTab: $sideTab, onBack: back, onMenu: toggleMenu) {
            Group {
                if let battleSession {
                    sessionContent(battleSession)
                } else if showsSetup {
                    WorldPanelViewport(minimumWidth: 700, minimumHeight: 380) { OnboardingFlowView() }
                } else if showsMenu {
                    WorldMenuView { route in open(route) }
                } else if app.router.isMatchFlowPresented {
                    WorldPanelViewport(minimumWidth: 740, minimumHeight: 380) { MatchFlowView() }
                } else if let route = app.router.path.last {
                    WorldPanelViewport(minimumWidth: 660, minimumHeight: 340) {
                        RouteDestination(route: route).id(route)
                    }
                } else {
                    HomeView(onInvite: invite, onStart: beginPlay)
                }
            }
        }
        .onChange(of: app.profile.onboardingCompleted) { _, completed in
            if completed { showsSetup = false }
        }
        .onChange(of: app.router.path) { _, _ in showsMenu = false }
        .onChange(of: app.router.isMatchFlowPresented) { _, shown in if shown { showsMenu = false } }
        .onAppear { app.audio.playMusic(.menu) }
    }

    @ViewBuilder private func sessionContent(_ session: WorldBattleSession) -> some View {
        switch session.phase {
        case .loading:
            WorldPanelViewport(minimumWidth: 850, minimumHeight: 440) {
                LoadingScreenView(launch: session.launch) { session.phase = .battle }
            }
        case .battle:
            Color.clear
        case .result(let outcome, let report):
            WorldPanelViewport(minimumWidth: 900, minimumHeight: 420) {
                if outcome.launch.config.mode == .ranked, report.rankAfter != nil, outcome.launch.replay == nil {
                    RankedResultFlowView(outcome: outcome, report: report) { app.dismissBattle() }
                } else {
                    MatchResultView(outcome: outcome, report: report) { app.dismissBattle() }
                }
            }
        }
    }

    private func beginPlay() {
        FlowFX.confirm(app)
        guard app.profile.onboardingCompleted else { showsSetup = true; return }
        showsMenu = false
        if let online = app.online, online.room.players.count > 1 || !online.isHost {
            app.router.push(.onlineLobby)
        } else {
            app.router.isMatchFlowPresented = true
        }
    }

    private func invite() {
        guard app.profile.onboardingCompleted else { showsSetup = true; return }
        sideTab = .friends
        app.ensurePartyRoom()
    }

    private func open(_ route: Route) {
        FlowFX.tap(app)
        showsMenu = false
        app.router.isMatchFlowPresented = false
        app.router.push(route)
    }

    private func toggleMenu() {
        guard !inSession else { return }
        FlowFX.tap(app)
        showsMenu.toggle()
    }

    private func back() {
        guard !inSession else { return }
        FlowFX.back(app)
        if showsMenu { showsMenu = false }
        else if showsSetup { showsSetup = false }
        else if app.router.isMatchFlowPresented { app.router.isMatchFlowPresented = false }
        else if !app.router.path.isEmpty { app.router.pop() }
        else { showsMenu = true }
    }
}

/// レイアウトを一か所で決める。メニューやポップアップもこのコンテンツ領域だけを置き換える。
struct WorldShellFrame<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var sideTab: PartySideTab
    let onBack: () -> Void
    var onMenu: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let sideWidth = geo.size.width * 0.34
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                        .frame(height: 76)
                        .padding(.horizontal, 12)
                    content()
                        .environment(\.isWorldShellEmbedded, true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(width: geo.size.width - sideWidth)
                PartySidePanel(tab: $sideTab)
                    .frame(width: sideWidth)
                    .environment(\.isWorldShellEmbedded, true)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 38, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("戻る・メニュー", "Back / Menu"))
            .accessibilityIdentifier("nav_back")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title).font(Theme.title(22)).foregroundStyle(Theme.gold)
                    if let subtitle {
                        Text(subtitle).font(Theme.heading(16)).foregroundStyle(Theme.success)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                difficulty
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Circle().fill(app.partyInviteRoom == nil ? Theme.textSecondary : Theme.success).frame(width: 6, height: 6)
                    Text(L("部屋コード", "Room code")).font(Theme.heading(10)).foregroundStyle(Theme.success)
                    if let onMenu {
                        Button(action: onMenu) {
                            Image(systemName: "square.grid.2x2.fill").font(.system(size: 13))
                                .foregroundStyle(Theme.cyan).frame(width: 30, height: 22)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("メニュー", "Menu"))
                        .accessibilityIdentifier("home_menu")
                    }
                }
                HStack(spacing: 8) {
                    Text(app.partyInviteRoom?.code ?? "— — —")
                        .font(Theme.title(23)).foregroundStyle(Theme.gold)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let room = app.partyInviteRoom {
                        Button {
                            UIPasteboard.general.string = room.code
                            app.showToast(L("部屋コードをコピーしました", "Room code copied"))
                        } label: { Image(systemName: "doc.on.doc").foregroundStyle(Theme.cyan) }
                        .accessibilityLabel(L("部屋コードをコピー", "Copy room code"))
                        ShareLink(item: "velstria://join?code=\(room.code)") {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.cyan)
                        }
                        .accessibilityLabel(L("部屋を共有", "Share room"))
                    }
                }
            }
            .frame(maxWidth: 152)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var difficulty: some View {
        Menu {
            ForEach(Difficulty.allCases, id: \.self) { value in
                Button(FlowText.difficulty(value)) {
                    app.profile.preferredDifficulty = value
                    if app.online?.isHost == true { app.online?.setBotDifficulty(value) }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "cpu")
                Text("AI: \(FlowText.difficulty(app.online?.room.botDifficulty ?? app.profile.preferredDifficulty))")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
            }
            .font(Theme.body(13)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.06, green: 0.18, blue: 0.36).opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.cyan.opacity(0.7)))
        }
        .disabled(app.online?.isHost == false)
        .accessibilityIdentifier("party_difficulty")
    }
}

/// 複雑なドラフト・スコア表も、同じ固定枠からはみ出さない座標系で描く。
struct WorldPanelViewport<Content: View>: View {
    var minimumWidth: CGFloat = 660
    var minimumHeight: CGFloat = 340
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, min(geo.size.width / minimumWidth, geo.size.height / minimumHeight))
            let safeScale = max(0.1, scale)
            content()
                .frame(width: geo.size.width / safeScale, height: geo.size.height / safeScale)
                .scaleEffect(safeScale, anchor: .topLeading)
        }
        .clipped()
    }
}

private struct WorldMenuView: View {
    let onSelect: (Route) -> Void
    @Environment(AppModel.self) private var app

    private var groups: [(String, String, [(String, String, Route)])] { [
        (L("バトル", "Battle"), "flag.checkered", [
            (L("オンライン", "Online"), "person.2.fill", .onlineLobby),
            (L("練習・AI戦", "Practice / AI"), "cpu", .customSetup),
            (L("ライジング", "Rising"), "trophy.fill", .rising),
            (L("マジックチェス", "Magic Chess"), "checkerboard.rectangle", .magicChess),
            (L("観戦", "Spectate"), "eye.fill", .spectateSetup),
            (L("リプレイ", "Replays"), "play.rectangle", .replays)]),
        (L("コレクション", "Collection"), "square.stack.3d.up.fill", [
            (L("ヒーロー", "Heroes"), "person.crop.square", .heroes),
            (L("装備", "Equipment"), "shield.fill", .items),
            (L("エンブレム", "Emblems"), "seal.fill", .emblems),
            (L("バトルスキル", "Battle Skills"), "bolt.fill", .spells),
            (L("外観", "Cosmetics"), "sparkles", .cosmetics),
            (L("バッグ", "Inventory"), "bag.fill", .inventory)]),
        (L("ショップ", "Shop"), "cart.fill", [
            (L("ストア", "Store"), "storefront.fill", .store),
            (L("スキン", "Skins"), "tshirt.fill", .skinStore),
            (L("ジェム", "Gems"), "diamond.fill", .currencyStore),
            (L("スターパス", "Star Pass"), "star.fill", .starPass),
            (L("購入の復元", "Restore"), "arrow.clockwise", .restorePurchases)]),
        (L("イベント", "Events"), "gift.fill", [
            (L("イベント", "Events"), "calendar", .events),
            (L("ミッション", "Missions"), "checklist", .missions),
            (L("メール", "Mail"), "envelope.fill", .mail),
            (L("お知らせ", "News"), "megaphone.fill", .notices),
            (L("ランキング", "Ranking"), "chart.bar.fill", .ranking)]),
        (L("プレイヤー", "Player"), "person.crop.circle", [
            (L("プロフィール", "Profile"), "person.fill", .profile),
            (L("戦績", "Records"), "clock.fill", .records),
            (L("ランク", "Rank"), "medal.fill", .rankOverview),
            (L("実績", "Achievements"), "rosette", .achievements),
            (L("設定", "Settings"), "gearshape.fill", .settings),
            (L("アカウント", "Account"), "person.crop.circle.badge.checkmark", .accountLink)])
    ] }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(spacing: 10) {
                        Image(systemName: group.1).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.cyan)
                        Text(group.0).font(Theme.heading(13)).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.6)
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(group.2.enumerated()), id: \.offset) { _, item in
                                    Button { onSelect(item.2) } label: {
                                        VStack(spacing: 3) {
                                            Image(systemName: item.1).font(.system(size: 16))
                                            Text(item.0).font(Theme.body(10)).lineLimit(1).minimumScaleFactor(0.7)
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("world_menu_\(item.2)")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 5).padding(.top, 14).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .worldShellCard()
                }
            }
            HStack {
                CurrencyBadge(kind: .coin, amount: app.profile.starlightCoin)
                CurrencyBadge(kind: .gem, amount: app.profile.totalGem)
                Spacer()
                Text("VELSIA").font(Theme.heading(12)).tracking(3).foregroundStyle(Theme.cyan.opacity(0.7))
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }
}

extension Route {
    var worldTitle: String {
        switch self {
        case .notices: return L("お知らせ", "News")
        case .mail: return L("メール", "Mail")
        case .profile: return L("プロフィール", "Profile")
        case .records: return L("戦績", "Records")
        case .achievements: return L("実績", "Achievements")
        case .ranking: return L("ランキング", "Leaderboard")
        case .rankOverview: return L("ランク", "Rank")
        case .rankRewards: return L("ランク報酬", "Rank rewards")
        case .accountLink: return L("アカウント", "Account")
        case .heroes, .heroDetail: return L("ヒーロー", "Heroes")
        case .skillDetail, .spells: return L("バトルスキル", "Battle skills")
        case .items, .itemDetail: return L("装備", "Equipment")
        case .buildEditor: return L("ビルド", "Build")
        case .emblems: return L("エンブレム", "Emblems")
        case .store, .productDetail: return L("ショップ", "Shop")
        case .skinStore: return L("スキン", "Skins")
        case .currencyStore: return L("ジェム", "Gems")
        case .restorePurchases: return L("購入の復元", "Restore purchases")
        case .inventory: return L("バッグ", "Inventory")
        case .cosmetics: return L("外観", "Cosmetics")
        case .emotes: return L("エモート", "Emotes")
        case .events, .eventDetail: return L("イベント", "Events")
        case .missions: return L("ミッション", "Missions")
        case .starPass: return L("スターパス", "Star Pass")
        case .settings: return L("設定", "Settings")
        case .controlSettings: return L("操作設定", "Controls")
        case .graphicsSettings: return L("画質設定", "Graphics")
        case .audioSettings: return L("音量設定", "Audio")
        case .languageSettings: return L("言語設定", "Language")
        case .notificationSettings: return L("通知設定", "Notifications")
        case .privacySettings: return L("プライバシー", "Privacy")
        case .support, .contact: return L("サポート", "Support")
        case .faq: return L("よくある質問", "FAQ")
        case .patchNotes: return L("アップデート", "Updates")
        case .tutorialMenu: return L("チュートリアル", "Tutorial")
        case .practiceSetup: return L("練習場", "Practice")
        case .credits: return L("クレジット", "Credits")
        case .replays: return L("リプレイ", "Replays")
        case .spectateSetup: return L("観戦", "Spectate")
        case .rising: return L("ライジング", "Rising")
        case .customSetup: return L("AI 対戦・カスタム", "AI / Custom")
        case .magicChess: return L("マジックチェス", "Magic Chess")
        case .onlineLobby: return L("オンライン対戦", "Online Match")
        }
    }
}
