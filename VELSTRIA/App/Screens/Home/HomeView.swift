import SwiftUI
import VelstriaCore

// UI007 ホーム。参照デザインの板（1024×471.5）を縦横同じ倍率でセーフエリアの内側に収めるロビーと、メニュードロワー。
// 配置の計算は HomeLogic.swift の HomeLayout / HomeLobbySlot（テストは HomeScreenTests）。

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()
    @State private var menuOpen = HomeDebug.startsMenuOpen
    /// ショーケースで選んでいるヒーロー（nil = 既定の選び方。画面内の状態だけでプロフィールには保存しない）。
    @State private var pickedHeroID: String? = HomeDebug.initialHeroID

    /// ホームが前面に見えているか。対戦・マジックチェスは fullScreenCover で開くのでホームは onDisappear にならない。
    /// 演出（TimelineView・繰り返しアニメ・3D）はこれが真の間だけ動かす。
    private var isFrontmost: Bool {
        app.router.path.isEmpty && !app.router.isMatchFlowPresented && app.activeBattle == nil
            && app.activeMagicChess == nil && scenePhase == .active
    }

    private var animates: Bool { isFrontmost && !reduceMotion }

    var body: some View {
        // 外側（セーフエリアを守る）でインセットを測り、内側（全画面）で配置する。
        // 全画面にした GeometryReader はインセットを 0 と報告するため。
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { geo in
                content(HomeLayout(size: geo.size, safeArea: insets))
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            now = Date()
            app.audio.playMusic(.menu)
        }
        // イベントの残り時間などを前面にいる間だけ更新する
        .task(id: isFrontmost) {
            guard isFrontmost else { return }
            now = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
        .fullScreenCover(isPresented: termsUpdateBinding) {
            TermsUpdateView().environment(app)
        }
    }

    private func content(_ layout: HomeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            HomeReferenceLobby(layout: layout, heroID: showcaseHeroID, animated: animates, now: now,
                               onMenu: openMenu, onPick: { pickedHeroID = $0 })
            if menuOpen {
                HomeMenuDrawer(layout: layout) { route in
                    closeMenu()
                    if let route { app.router.push(route) }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    /// ショーケースに出すヒーロー。
    private var showcaseHeroID: String {
        if let id = pickedHeroID, app.master.hero(id) != nil { return id }
        return HomeShowcaseLogic.initialHero(lastPicked: app.profile.lastPickedHeroID, avatar: app.profile.avatarHeroID,
                                             isKnown: { app.master.hero($0) != nil })
    }

    private func openMenu() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)) { menuOpen = true }
    }

    private func closeMenu() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { menuOpen = false }
    }

    /// 規約が改定されていたら再同意を求める（戦闘・対戦フロー表示中は出さない）。
    private var termsUpdateBinding: Binding<Bool> {
        Binding(
            get: {
                app.profile.onboardingCompleted
                    && app.profile.acceptedTermsVersion < FeatureFlags.currentTermsVersion
                    && app.activeBattle == nil
                    && !app.router.isMatchFlowPresented
            },
            set: { _ in }
        )
    }
}

/// 検証用の起動引数（DebugLaunch.swift 冒頭の一覧を参照。出荷ビルドでは DebugLaunch.args が空なので常に既定値）。
enum HomeDebug {
    static var startsFriendsCollapsed: Bool { DebugLaunch.value(after: "-homeRail") == "collapsed" }
    static var startsMenuOpen: Bool { DebugLaunch.args.contains("-homeMenu") }
    static var initialHeroID: String? { DebugLaunch.value(after: "-homeHero") }
}

/// 参照デザインのロビー。部品は板の座標（HomeLobbySlot）で置き、板ごと HomeLayout の倍率で縮める。
/// 背景とフッターの帯だけは板の外の余白まで画面いっぱいに描く。
private struct HomeReferenceLobby: View {
    let layout: HomeLayout
    let heroID: String
    let animated: Bool
    let now: Date
    let onMenu: () -> Void
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var app
    @State private var friendsCollapsed = HomeDebug.startsFriendsCollapsed
    private let cyan = Color(red: 0.60, green: 0.91, blue: 1)
    private let purple = Color(red: 0.27, green: 0.22, blue: 0.72)

    var body: some View {
        backdrop
            .frame(width: layout.size.width, height: layout.size.height)
            .overlay(alignment: .topLeading) {
                canvas
                    .frame(width: HomeLayout.board.width, height: HomeLayout.board.height)
                    .scaleEffect(layout.scale, anchor: .topLeading)
                    .offset(x: layout.boardRect.minX, y: layout.boardRect.minY)
            }
            .clipped()
            .task { app.friends.start(); app.friends.refreshPresence() }
    }

    /// 画面いっぱいの背景（板の外の余白も埋める）とフッターの帯。
    private var backdrop: some View {
        let band = layout.footerBandRect
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.17, blue: 0.30), Color(red: 0.27, green: 0.32, blue: 0.88), .cyan],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("HomeBackdrop").resizable().scaledToFill()
                .frame(width: layout.size.width, height: layout.size.height).opacity(0.22).clipped()
            LinearGradient(colors: [Color(red: 0.91, green: 0.80, blue: 0.98), .white, cyan], startPoint: .leading, endPoint: .trailing)
                .overlay(alignment: .top) { Rectangle().fill(cyan).frame(height: 1) }
                .frame(width: band.width, height: band.height)
                .offset(x: band.minX, y: band.minY)
        }
        .allowsHitTesting(false)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            diagonalRibbons
            HomeHeroArt(heroID: heroID, skinID: app.profile.equippedSkins[heroID], size: CGSize(width: 560, height: 560), animated: animated)
                .frame(width: 560, height: 560).position(x: 345, y: 264)
                .allowsHitTesting(false)
            Button { FlowFX.tap(app); app.router.push(.heroDetail(heroID)) } label: { Color.clear.contentShape(Rectangle()) }
                .accessibilityLabel(L("ヒーロー詳細", "Hero details"))
                .accessibilityIdentifier("home_hero")
                .frame(width: 510, height: 320).position(x: 480, y: 245)
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > 50, abs(value.translation.width) > abs(value.translation.height) else { return }
                    let roster = HomeShowcaseLogic.roster(owned: app.profile.ownedHeroIDs, masterOrder: app.master.heroes.map(\.heroID))
                    onPick(HomeShowcaseLogic.neighbor(of: heroID, in: roster, step: value.translation.width < 0 ? 1 : -1))
                })
            header
            promotions
            friendPanel
            footer
            firstWinBanner
        }
        .buttonStyle(HomePressStyle())
    }

    private var diagonalRibbons: some View {
        ZStack {
            ForEach(0..<4) { i in
                Rectangle().fill([cyan.opacity(0.25), purple.opacity(0.6), Color.cyan.opacity(0.3), Color.pink.opacity(0.3)][i])
                    .frame(width: 1400, height: i == 1 ? 74 : 12)
                    .rotationEffect(.degrees(-34)).position(x: 490, y: CGFloat(70 + i * 62))
            }
        }.allowsHitTesting(false)
    }

    private func referenceAvatar(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let portrait = PortraitArt.hero(app.profile.avatarHeroID) {
                Image(uiImage: portrait).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.square.fill").resizable().scaledToFit().foregroundStyle(cyan)
            }
        }
        .frame(width: width, height: height).clipped()
        .overlay(Rectangle().stroke(HomeStyle.goldGradient, lineWidth: 1))
    }

    private var header: some View {
        Group {
            Button { FlowFX.tap(app); app.router.push(.profile) } label: {
                HStack(spacing: 9) {
                    referenceAvatar(width: 35, height: 35)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.profile.displayName.isEmpty ? "Player" : app.profile.displayName).font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 5) {
                            Image(systemName: "shield.fill").foregroundStyle(cyan)
                            Text("\(app.profile.accountLevel)")
                            HomeBar(value: Double(app.profile.accountXP) / Double(max(1, FlowAccountXP.required(forLevel: app.profile.accountLevel))), tint: .cyan).frame(width: 60, height: 5)
                        }.font(.system(size: 12))
                    }
                }.foregroundStyle(.white)
            }.accessibilityIdentifier("home_profile").homePlaced(in: HomeLobbySlot.profile)
            icon("headphones", L("サポート", "Support"), .support).homePlaced(in: HomeLobbySlot.support)
            icon("seal", L("実績", "Achievements"), .achievements, badge: HomeBadges.claimableAchievements(app.profile))
                .homePlaced(in: HomeLobbySlot.achievements)
            Button(action: { FlowFX.tap(app); onMenu() }) {
                Image(systemName: "line.3.horizontal").font(.system(size: 22)).foregroundStyle(cyan).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("メニュー", "Menu")).accessibilityIdentifier("home_menu").homePlaced(in: HomeLobbySlot.menu)
            Button { FlowFX.tap(app); app.router.push(.currencyStore) } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.circle.fill").foregroundStyle(Theme.gold)
                        Text(HomeFormat.currency(app.profile.starlightCoin, compact: false))
                    }.frame(width: 76, alignment: .leading)
                    HStack(spacing: 3) {
                        Image(systemName: "diamond.fill").foregroundStyle(Theme.cyan)
                        Text("\(app.profile.totalGem)")
                    }.frame(width: 60, alignment: .leading)
                    Text("+").font(.system(size: 25, weight: .bold)).foregroundStyle(.yellow)
                }.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 180, height: 25).background(purple.opacity(0.35))
            }
            .accessibilityLabel(L("コイン \(app.profile.starlightCoin)、ジェム \(app.profile.totalGem)",
                                  "\(app.profile.starlightCoin) coins, \(app.profile.totalGem) gems"))
            .accessibilityIdentifier("home_currency").homePlaced(in: HomeLobbySlot.currency)
            HStack(spacing: 0) {
                icon("trophy.fill", L("ランキング", "Leaderboard"), .ranking)
                icon("chart.bar.fill", L("戦績", "Records"), .records)
                icon("play.rectangle.fill", L("観戦", "Spectate"), .spectateSetup)
                icon("envelope.fill", L("メール", "Mail"), .mail, badge: HomeBadges.mail(app.profile, now: now))
                icon("gearshape.fill", L("設定", "Settings"), .settings)
            }.homePlaced(in: HomeLobbySlot.headerIcons)
        }
    }

    /// アイコンのボタン。受け取れる物があるときは右上に赤い点（数字は出さない）。識別子は home_<遷移先の名前>。
    private func icon(_ symbol: String, _ title: String, _ route: Route, badge: Int = 0) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(cyan)
                .frame(width: 38, height: 44)
                .overlay(alignment: .topTrailing) { RedDot(shown: badge > 0).offset(x: -4, y: 6) }
        }
        .accessibilityLabel(badge > 0 ? title + L("（受け取れる物があります）", " (rewards available)") : title)
        .accessibilityIdentifier("home_\(String(describing: route))")
    }

    private var promotions: some View {
        Group {
            promo("LoadingKeyArt", L("イベント", "Events"), .events, badge: HomeBadges.eventMissions(app.profile, now: now))
                .homePlaced(in: HomeLobbySlot.events)
            promo("HomeBackdrop", "STAR PASS", .starPass, badge: HomeBadges.starPass(app.profile))
                .homePlaced(in: HomeLobbySlot.starPass)
            VStack(spacing: 8) {
                railLink("scalemass", L("ストア", "Store"), .store)
                railLink("checklist", L("ミッション", "Missions"), .missions, badge: HomeBadges.claimableMissions(app.profile))
            }.homePlaced(in: HomeLobbySlot.rail)
            icon("rectangle.portrait.on.rectangle.portrait", L("お知らせ", "Notices"), .notices, badge: HomeBadges.unreadNotices(app.profile))
                .homePlaced(in: HomeLobbySlot.notices)
        }
    }

    private func promo(_ image: String, _ title: String, _ route: Route, badge: Int) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            GeometryReader { g in
                Image(image).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                    .overlay(alignment: .bottomLeading) { Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: 2).padding(3) }
                    .overlay(Rectangle().stroke(cyan.opacity(0.75), lineWidth: 1))
                    .overlay(alignment: .topTrailing) { RedDot(shown: badge > 0).offset(x: 3, y: -3) }
            }
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("home_\(String(describing: route))")
    }

    private func railLink(_ symbol: String, _ title: String, _ route: Route, badge: Int = 0) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: 25))
                Text(title).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(cyan).frame(width: 48, height: 44)
                .overlay(alignment: .topTrailing) { RedDot(shown: badge > 0) }
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("home_\(String(describing: route))")
    }

    private var friendPanel: some View {
        let slot = HomeLobbySlot.friends
        return Group {
            if !friendsCollapsed {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            if app.friends.friends.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "person.2.fill").font(.system(size: 30))
                                    Text(L("フレンドと遊ぼう", "Play with friends")).font(.system(size: 13))
                                    Text(L("フレンドを追加して\nパーティを組もう", "Add friends and\nform a party")).font(.system(size: 11)).multilineTextAlignment(.center)
                                }.foregroundStyle(cyan).frame(width: 146, height: 232)
                            }
                            ForEach(app.friends.friends) { friend in
                                Button { FlowFX.tap(app); app.router.push(.onlineLobby) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.crop.square.fill").font(.system(size: 35))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(FriendNames.display(friend.name)).lineLimit(1)
                                            Text(app.friends.isFriendOnline(friend.code) ? L("オンライン", "Online") : L("オフライン", "Offline"))
                                                .font(.system(size: 9))
                                        }.font(.system(size: 11))
                                        Spacer(minLength: 0)
                                    }.foregroundStyle(cyan).padding(5).frame(height: 55)
                                        .background(purple.opacity(0.18))
                                }
                                Divider().overlay(cyan.opacity(0.3))
                            }
                        }
                    }
                    icon("person.badge.plus", L("フレンド", "Friends"), .onlineLobby, badge: HomeBadges.friendRequests(app.friends))
                        .frame(height: 31).frame(maxWidth: .infinity).background(cyan.opacity(0.14))
                }.background(Color(red: 0.15, green: 0.22, blue: 0.64).opacity(0.52))
                    .homePlaced(in: slot)
            }
            Button { FlowFX.tap(app); friendsCollapsed.toggle() } label: {
                Image(systemName: friendsCollapsed ? "chevron.left.2" : "chevron.right.2")
                    .foregroundStyle(cyan).frame(width: 22, height: 68).background(purple.opacity(0.65))
                    .overlay(alignment: .topLeading) { RedDot(shown: friendsCollapsed && HomeBadges.friendRequests(app.friends) > 0) }
            }
            .accessibilityLabel(friendsCollapsed ? L("フレンド欄を開く", "Show friends") : L("フレンド欄を畳む", "Hide friends"))
            .accessibilityIdentifier("home_friends_toggle")
            .position(x: friendsCollapsed ? slot.maxX - 11 : slot.minX - 11, y: slot.midY)
        }
    }

    private var footer: some View {
        Group {
            Button { FlowFX.tap(app); app.router.push(.profile) } label: {
                referenceAvatar(width: 112, height: 53)
                    .frame(width: 112, height: 53).background(purple.opacity(0.9))
                    .overlay(Rectangle().stroke(cyan, lineWidth: 2))
            }
            .accessibilityLabel(L("プロフィール", "Profile"))
            .accessibilityIdentifier("home_avatar").homePlaced(in: HomeLobbySlot.avatar)
            HStack(spacing: 0) {
                footerLink("shield.lefthalf.filled", L("戦闘準備", "Prep"), .items)
                footerLink("person.fill", L("ヒーロー", "Heroes"), .heroes)
                footerLink("diamond", L("コレクション", "Collection"), .cosmetics)
                footerLink("bag.fill", L("バッグ", "Bag"), .inventory)
            }.homePlaced(in: HomeLobbySlot.footerTabs)
            Button { FlowFX.tap(app); app.router.push(.emblems) } label: {
                Image(systemName: "shield.checkered").font(.system(size: 30)).foregroundStyle(.yellow).frame(width: 52, height: 48).background(purple)
                    .overlay(alignment: .topTrailing) { RedDot(shown: HomeBadges.emblemChest(app.profile, now: now) > 0).offset(x: -3, y: 3) }
            }
            .accessibilityLabel(L("エンブレム", "Emblems"))
            .accessibilityIdentifier("home_emblems").homePlaced(in: HomeLobbySlot.emblems)
            Button { FlowFX.tap(app); app.router.push(.rankOverview) } label: {
                VStack(spacing: 0) {
                    RankEmblemView(tier: app.profile.rank.tier, size: 50)
                    Text(RankService.displayName(app.profile.rank)).font(.system(size: 11)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }.frame(width: 56, height: 77).background(purple.opacity(0.8))
                    .overlay(alignment: .topTrailing) { RedDot(shown: HomeBadges.claimableRankRewards(app.profile) > 0).offset(x: -3, y: 3) }
            }
            .accessibilityLabel(L("ランク", "Rank"))
            .accessibilityIdentifier("home_rank").homePlaced(in: HomeLobbySlot.rank)
            Button { FlowFX.confirm(app); MatchFlowIntent.present(nil, app: app) } label: {
                VStack(spacing: 0) {
                    playStars
                    Text(L("対戦開始", "BATTLE")).font(.system(size: 28, weight: .black)).foregroundStyle(Color(red: 0.22, green: 0.16, blue: 0.09))
                }.frame(width: 190, height: 66)
                    .background(LinearGradient(colors: [.yellow, Color(red: 1, green: 0.95, blue: 0.44), .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(HomeChamfer(cut: 15, corners: .antiDiagonal))
                    .overlay(HomeChamfer(cut: 15, corners: .antiDiagonal).stroke(HomeStyle.goldGradient, lineWidth: 3))
                    .shadow(color: .pink.opacity(0.8), radius: 5)
            }.accessibilityIdentifier("home_play").homePlaced(in: HomeLobbySlot.play)
        }
    }

    /// 対戦開始ボタンの星（ティアごとの星の数。ミシックは星の累計）。
    @ViewBuilder
    private var playStars: some View {
        let rank = app.profile.rank
        if rank.tier == .mythic {
            Label("\(rank.stars)", systemImage: "star.fill")
                .font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.gold)
        } else {
            RankStarsView(stars: rank.stars, maxStars: RankService.maxStars(rank.tier), size: 16)
        }
    }

    private func footerLink(_ symbol: String, _ title: String, _ route: Route) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(purple)
                .frame(maxWidth: .infinity).frame(height: 49)
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("home_\(String(describing: route))")
    }

    private var firstWinBanner: some View {
        Button { FlowFX.tap(app); app.router.push(.missions) } label: {
            Label(HomeBadges.firstWinAvailable(app.profile, now: now) ? L("本日の初勝利ボーナス +300", "First win of the day +300")
                                                                       : L("初勝利ボーナス獲得済み", "First win bonus claimed"),
                  systemImage: "gift.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(purple)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 195, height: 29).background(.white.opacity(0.94))
                .clipShape(HomeChamfer(cut: 10))
                .overlay(HomeChamfer(cut: 10).stroke(HomeStyle.goldGradient, lineWidth: 2))
        }
        .accessibilityIdentifier("home_first_win").homePlaced(in: HomeLobbySlot.firstWin)
    }
}

/// 赤い点（数字は出さない。MLBB 2.2.16 と同じく受け取れる物があるときだけ）。
private struct RedDot: View {
    let shown: Bool

    var body: some View {
        if shown {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}
