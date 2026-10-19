import SwiftUI
import VelstriaCore

// UI007 ホーム。参照デザインの比率で配置するロビーと、既存のメニュードロワー。
// ドロワーのセーフエリア計算は HomeMetrics を引き続き使用する。

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
                content(HomeMetrics(size: geo.size, safeArea: insets))
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

    private func content(_ m: HomeMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            HomeReferenceLobby(heroID: showcaseHeroID, animated: animates, now: now, onMenu: openMenu, onPick: { pickedHeroID = $0 })
                .frame(width: m.size.width, height: m.size.height)
            if menuOpen {
                HomeMenuDrawer(metrics: m) { route in
                    closeMenu()
                    if let route { app.router.push(route) }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(width: m.size.width, height: m.size.height)
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
    static var startsRailCollapsed: Bool { DebugLaunch.value(after: "-homeRail") == "collapsed" }
    static var startsMenuOpen: Bool { DebugLaunch.args.contains("-homeMenu") }
    static var initialHeroID: String? { DebugLaunch.value(after: "-homeHero") }
    static var starts3D: Bool { DebugLaunch.args.contains("-home3D") }
}

/// Reference layout uses a 2048 × 943 design canvas. Coordinates stay proportional
/// across landscape phones; content is live, never baked into a screenshot.
private struct HomeReferenceLobby: View {
    let heroID: String
    let animated: Bool
    let now: Date
    let onMenu: () -> Void
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var app
    @State private var friendsCollapsed = HomeDebug.startsRailCollapsed
    private let cyan = Color(red: 0.60, green: 0.91, blue: 1)
    private let purple = Color(red: 0.27, green: 0.22, blue: 0.72)

    var body: some View {
        GeometryReader { geo in
            canvas
                .frame(width: 1024, height: 471.5)
                .scaleEffect(x: geo.size.width / 1024, y: geo.size.height / 471.5, anchor: .topLeading)
        }
        .clipped()
        .task { app.friends.start(); app.friends.refreshPresence() }
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.17, blue: 0.30), Color(red: 0.27, green: 0.32, blue: 0.88), .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("HomeBackdrop").resizable().scaledToFill().frame(width: 1024, height: 471.5).opacity(0.22).clipped()
            diagonalRibbons
            HomeHeroArt(heroID: heroID, skinID: app.profile.equippedSkins[heroID], size: CGSize(width: 560, height: 560), animated: animated)
                .frame(width: 560, height: 560).position(x: 345, y: 264)
                .allowsHitTesting(false)
            Button { app.router.push(.heroDetail(heroID)) } label: { Color.clear.contentShape(Rectangle()) }
                .accessibilityLabel(L("ヒーロー詳細", "Hero details"))
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
            rewardBanner
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
            Button { app.router.push(.profile) } label: {
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
            }.accessibilityIdentifier("home_profile").homePlaced(in: CGRect(x: 61, y: 10, width: 140, height: 36))
            icon("headphones", "サポート", .support).position(x: 224, y: 25)
            icon("seal", "実績", .achievements).position(x: 264, y: 25)
            Button(action: onMenu) { Image(systemName: "line.3.horizontal").font(.system(size: 22)).foregroundStyle(cyan).frame(width: 44, height: 44) }
                .accessibilityLabel("メニュー").accessibilityIdentifier("home_menu").position(x: 305, y: 25)
            Button { app.router.push(.currencyStore) } label: {
                HStack(spacing: 8) {
                    Label(HomeFormat.currency(app.profile.starlightCoin, compact: false), systemImage: "dollarsign.circle.fill").frame(width: 76, alignment: .leading)
                    Label("\(app.profile.totalGem)", systemImage: "diamond.fill").frame(width: 60, alignment: .leading)
                    Text("+").font(.system(size: 25, weight: .bold)).foregroundStyle(.yellow)
                }.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 180, height: 25).background(purple.opacity(0.35))
            }.accessibilityIdentifier("home_currency").position(x: 650, y: 25)
            HStack(spacing: 0) {
                icon("trophy.fill", "ランキング", .ranking)
                icon("chart.bar.fill", "戦績", .records)
                icon("play.rectangle.fill", "観戦", .spectateSetup)
                icon("envelope.fill", "メール", .mail, badge: HomeBadges.unreadMail(app.profile, now: now))
                icon("gearshape.fill", "設定", .settings)
            }.position(x: 842, y: 25)
        }
    }

    private func icon(_ symbol: String, _ title: String, _ route: Route, badge: Int = 0) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(cyan)
                .frame(width: 38, height: 44)
                .overlay(alignment: .topTrailing) { if badge > 0 { Circle().fill(.pink).frame(width: 7, height: 7).offset(x: -4, y: 6) } }
        }.accessibilityLabel(title).accessibilityIdentifier("home_\(String(describing: route))")
    }

    private var promotions: some View {
        Group {
            promo("LoadingKeyArt", "イベント", .events).homePlaced(in: CGRect(x: 61, y: 63, width: 104, height: 38))
            promo("HomeBackdrop", "STAR PASS", .starPass).homePlaced(in: CGRect(x: 61, y: 111, width: 104, height: 38))
            VStack(spacing: 8) {
                railLink("scalemass", "ストア", .store)
                railLink("party.popper", "イベント", .events)
                railLink("checklist", "ミッション", .missions)
            }.homePlaced(in: CGRect(x: 57, y: 157, width: 48, height: 149))
            icon("rectangle.portrait.on.rectangle.portrait", "お知らせ", .notices, badge: HomeBadges.unreadNotices(app.profile)).position(x: 200, y: 83)
        }
    }

    private func promo(_ image: String, _ title: String, _ route: Route) -> some View {
        Button { app.router.push(route) } label: {
            GeometryReader { g in
                Image(image).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                    .overlay(alignment: .bottomLeading) { Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: 2).padding(3) }
                    .overlay(Rectangle().stroke(cyan.opacity(0.75), lineWidth: 1))
            }
        }.accessibilityLabel(title)
    }

    private func railLink(_ symbol: String, _ title: String, _ route: Route) -> some View {
        Button { app.router.push(route) } label: {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: 25))
                Text(title).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(cyan).frame(width: 48, height: 44)
        }.accessibilityLabel(title)
    }

    private var friendPanel: some View {
        Group {
            if !friendsCollapsed {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            if app.friends.friends.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "person.2.fill").font(.system(size: 30))
                                    Text(L("フレンドと遊ぼう", "Play with friends")).font(.system(size: 13))
                                    Text(L("フレンドを追加して\nパーティを組もう", "Add friends and\nform a party")).font(.system(size: 11)).multilineTextAlignment(.center)
                                    Button(L("フレンドを追加", "Add friends")) { app.router.push(.onlineLobby) }.font(.system(size: 12)).padding(8).background(cyan.opacity(0.16))
                                }.foregroundStyle(cyan).frame(width: 146, height: 232)
                            }
                            ForEach(app.friends.friends) { friend in
                                Button { app.router.push(.onlineLobby) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.crop.square.fill").font(.system(size: 35))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(FriendNames.display(friend.name)).lineLimit(1)
                                            Text(app.friends.isFriendOnline(friend.code) ? "オンライン" : "オフライン").font(.system(size: 9))
                                        }.font(.system(size: 11))
                                        Spacer(minLength: 0)
                                    }.foregroundStyle(cyan).padding(5).frame(height: 55)
                                        .background(purple.opacity(0.18))
                                }
                                Divider().overlay(cyan.opacity(0.3))
                            }
                        }
                    }
                    HStack(spacing: 3) {
                        icon("person.2.fill", "オンライン", .onlineLobby)
                        icon("person.badge.plus", "フレンド追加", .onlineLobby)
                        icon("shield.lefthalf.filled", "ランク", .rankOverview)
                    }.frame(height: 31).frame(maxWidth: .infinity).background(cyan.opacity(0.14))
                }.background(Color(red: 0.15, green: 0.22, blue: 0.64).opacity(0.52))
                    .homePlaced(in: CGRect(x: 825, y: 70, width: 146, height: 265))
            }
            Button { friendsCollapsed.toggle() } label: {
                Image(systemName: friendsCollapsed ? "chevron.left.2" : "chevron.right.2")
                    .foregroundStyle(cyan).frame(width: 22, height: 68).background(purple.opacity(0.65))
            }.accessibilityLabel("フレンド欄を切り替え").position(x: friendsCollapsed ? 960 : 814, y: 203)
        }
    }

    private var footer: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.91, green: 0.80, blue: 0.98), .white, cyan], startPoint: .leading, endPoint: .trailing)
                .overlay(alignment: .top) { Rectangle().fill(cyan).frame(height: 1) }
                .homePlaced(in: CGRect(x: 0, y: 379, width: 1024, height: 92.5))

            // 一列で幅を分配し、ランク表示と開始ボタンの重なりを防ぐ。
            // 下端にはホームインジケータ用の余白を残す。
            HStack(spacing: 10) {
                Button { app.router.push(.profile) } label: {
                    referenceAvatar(width: 64, height: 48)
                        .overlay(Rectangle().stroke(cyan, lineWidth: 1))
                }.accessibilityLabel(L("プロフィール", "Profile"))

                HStack(spacing: 0) {
                    footerLink("shield.lefthalf.filled", L("戦闘準備", "Prepare"), .items)
                    footerLink("person.fill", L("ヒーロー", "Heroes"), .heroes)
                    footerLink("diamond", L("コレクション", "Collection"), .cosmetics)
                    footerLink("bag.fill", L("バッグ", "Bag"), .inventory)
                }.frame(maxWidth: .infinity)

                Button { app.router.push(.emblems) } label: {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 25))
                        .foregroundStyle(purple)
                        .frame(width: 44, height: 52)
                        .background(purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel(L("エンブレム", "Emblems"))

                Button { app.router.push(.rankOverview) } label: {
                    VStack(spacing: 2) {
                        RankEmblemView(tier: app.profile.rank.tier, size: 36)
                        Text(RankService.displayName(app.profile.rank))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(purple)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }.frame(width: 76, height: 60)
                }.accessibilityLabel(L("ランク", "Rank"))

                Button { FlowFX.confirm(app); MatchFlowIntent.present(nil, app: app) } label: {
                    VStack(spacing: 2) {
                        RankStarsView(stars: app.profile.rank.stars, size: 12)
                        Text(L("対戦開始", "BATTLE"))
                            .font(.system(size: 25, weight: .black))
                            .foregroundStyle(Color(red: 0.22, green: 0.16, blue: 0.09))
                    }.frame(width: 180, height: 60)
                        .background(LinearGradient(colors: [HomeStyle.goldLight, .yellow, Theme.gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(HomeChamfer(cut: 12, corners: .antiDiagonal))
                        .overlay(HomeChamfer(cut: 12, corners: .antiDiagonal).strokeBorder(HomeStyle.goldGradient, lineWidth: 2))
                        .shadow(color: Theme.gold.opacity(0.3), radius: 4, y: 2)
                }.accessibilityIdentifier("home_play")
            }
            .homePlaced(in: CGRect(x: 61, y: 387, width: 910, height: 60))
        }
    }

    private func footerLink(_ symbol: String, _ title: String, _ route: Route) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }.foregroundStyle(purple)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .contentShape(Rectangle())
        }.accessibilityLabel(title)
    }

    private var rewardBanner: some View {
        Button { app.router.push(.missions) } label: {
            Label(HomeBadges.firstWinAvailable(app.profile, now: now) ? "本日の初勝利ボーナス +300" : "初勝利ボーナス獲得済み", systemImage: "gift.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(purple)
                .frame(width: 195, height: 29).background(.white.opacity(0.94))
                .clipShape(HomeChamfer(cut: 10))
                .overlay(HomeChamfer(cut: 10).stroke(HomeStyle.goldGradient, lineWidth: 2))
        }.homePlaced(in: CGRect(x: 623, y: 309, width: 195, height: 29))
    }
}
