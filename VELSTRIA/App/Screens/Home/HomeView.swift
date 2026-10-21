import SwiftUI
import VelstriaCore

// UI007 ホーム。採用案 Celestial Saber（docs/design/CELESTIAL_HOME.md）のロビーと、メニュードロワー。
// 部品の位置は HomeLogic.swift の HomeLobbySlot（板 1024 × 512 の座標）、倍率と置き場所は HomeLayout。

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()
    @State private var menuOpen = HomeDebug.startsMenuOpen

    /// ホームが前面に見えているか。対戦・マジックチェスは fullScreenCover で開くのでホームは onDisappear にならない。
    /// 演出（TimelineView・繰り返しアニメ）はこれが真の間だけ動かす。
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

    private func content(_ m: HomeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            HomeReferenceLobby(layout: m, animated: animates, now: now, onMenu: openMenu)
                .frame(width: m.size.width, height: m.size.height)
            if menuOpen {
                HomeMenuDrawer(layout: m) { route in
                    closeMenu()
                    if let route { app.router.push(route) }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(width: m.size.width, height: m.size.height)
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
}

/// 採用コンセプトの 1774 × 887 を 1024 × 512 の座標に正規化。
/// 装飾アトラスと実データを分離し、ナビゲーションはすべて実ボタンにする。
private struct HomeReferenceLobby: View {
    let layout: HomeLayout
    let animated: Bool
    let now: Date
    let onMenu: () -> Void
    @Environment(AppModel.self) private var app
    @State private var friendsCollapsed = HomeDebug.startsFriendsCollapsed
    private let ice = Color(red: 0.65, green: 0.84, blue: 1)
    private let ink = Color(red: 0.015, green: 0.045, blue: 0.09)

    var body: some View {
        GeometryReader { geo in
            Image("CelestialLobby").resizable().scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height).clipped()
                .blur(radius: 20).overlay(Color.black.opacity(0.7))
            canvas
                .frame(width: HomeLayout.board.width, height: HomeLayout.board.height)
                .scaleEffect(layout.scale, anchor: .topLeading)
                .offset(x: layout.boardRect.minX, y: layout.boardRect.minY)
        }
        .clipped()
        .task { app.friends.start(); app.friends.refreshPresence() }
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Image("CelestialLobby").resizable().frame(width: HomeLayout.board.width, height: HomeLayout.board.height)
                .scaleEffect(1.008)
                .modifier(HomeAmbientMotion(animated: animated, travel: 1, duration: 6))
                .overlay {
                    if animated {
                        CelestialAtmosphere().allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            // 背景はその季節のキービジュアル（MLBB の看板ヒーローに当たる。3D にはしない）。ヒーロー一覧への入口として扱う。
            Button { app.router.push(.heroes) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(L("ヒーローを見る", "Explore heroes"))
                .accessibilityIdentifier("home_heroes_visual")
                .homePlaced(in: HomeLobbySlot.keyVisual)
            header
            promotions
            if !friendsCollapsed { friendPanel.homePlaced(in: HomeLobbySlot.friends) }
            footer
            CelestialFrame(animated: animated).padding(7)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .buttonStyle(HomeAmbientButtonStyle(animated: animated))
    }

    private var header: some View {
        Group {
            Text("CELESTIAL SABER").font(.system(size: 12, design: .serif)).tracking(3)
                .foregroundStyle(ice).position(x: 157, y: 16)
            HStack(spacing: 7) {
                Image(systemName: "sparkle").font(.system(size: 18, weight: .ultraLight))
                Text("VELSTRIA").font(.system(size: 16, weight: .regular, design: .serif)).tracking(5)
            }.foregroundStyle(ice).position(x: 509, y: 16)
            Button { app.router.push(.profile) } label: {
                HStack(spacing: 9) {
                    // 受け取れる実績はプロフィール（の実績）から受け取る
                    avatar(app.profile.avatarHeroID, size: 49)
                        .overlay(alignment: .topTrailing) { CelestialDot(shown: HomeBadges.claimableAchievements(app.profile) > 0).offset(x: -2, y: 2) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.profile.displayName.isEmpty ? "Player" : app.profile.displayName)
                            .font(.system(size: 14, design: .serif)).lineLimit(1)
                        HStack(spacing: 5) {
                            Text("Lv.\(app.profile.accountLevel)").font(.system(size: 12, design: .serif))
                            CelestialProgressBar(value: Double(app.profile.accountXP) / Double(max(1, FlowAccountXP.required(forLevel: app.profile.accountLevel))), tint: .cyan, height: 5).frame(width: 54)
                        }
                    }
                }
            }.accessibilityIdentifier("home_profile").homePlaced(in: HomeLobbySlot.profile)
            HStack(spacing: 10) {
                currency(.coin, HomeFormat.currency(app.profile.starlightCoin, compact: false), id: "home_currency_coin")
                currency(.gem, HomeFormat.currency(app.profile.totalGem, compact: false), id: "home_currency_gem")
                utility("envelope.fill", L("メール", "Mail"), .mail, id: "home_mail", badge: HomeBadges.mail(app.profile, now: now))
                Button { friendsCollapsed.toggle() } label: {
                    Image(systemName: "person.2.fill").font(.system(size: 23)).frame(width: 32, height: 38)
                        .overlay(alignment: .topTrailing) { CelestialDot(shown: HomeBadges.friendRequests(app.friends) > 0) }
                }
                .accessibilityLabel(L("フレンド欄を切り替え", "Toggle friends")).accessibilityIdentifier("home_friends_toggle")
                utility("gearshape.fill", L("設定", "Settings"), .settings, id: "home_settings")
                Button(action: onMenu) { Image(systemName: "line.3.horizontal").font(.system(size: 21)).frame(width: 32, height: 38) }
                    .accessibilityLabel(L("メニュー", "Menu")).accessibilityIdentifier("home_menu")
            }.foregroundStyle(ice).homePlaced(in: HomeLobbySlot.headerIcons)
        }
    }

    private func avatar(_ id: String, size: CGFloat) -> some View {
        Group {
            if let portrait = PortraitArt.hero(id) {
                Image(uiImage: portrait).resizable().scaledToFill()
            } else { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit() }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(HomeStyle.goldGradient, lineWidth: 1))
        .shadow(color: ice.opacity(0.4), radius: 4)
    }

    private func currency(_ kind: CurrencyIcon.Kind, _ value: String, id: String) -> some View {
        Button { app.router.push(.currencyStore) } label: {
            HStack(spacing: 5) {
                CurrencyIcon(kind: kind, size: 17)
                Text(value).font(.system(size: 13, design: .serif)).lineLimit(1).minimumScaleFactor(0.65)
                Image(systemName: "plus").font(.system(size: 12, weight: .light))
            }.padding(.horizontal, 6).frame(width: 99, height: 27)
                .background(ink.opacity(0.85), in: HomeChamfer(cut: 7))
                .overlay(HomeChamfer(cut: 7).stroke(ice.opacity(0.45), lineWidth: 0.6))
        }.accessibilityLabel(L("通貨ストア", "Currency store") + " " + value).accessibilityIdentifier(id)
    }

    private func utility(_ symbol: String, _ title: String, _ route: Route, id: String, badge: Int = 0) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            Image(systemName: symbol).font(.system(size: 22)).frame(width: 32, height: 38)
                .overlay(alignment: .topTrailing) { CelestialDot(shown: badge > 0) }
        }.accessibilityLabel(title).accessibilityIdentifier(id)
    }

    // MARK: 左のカード

    /// 左上のカードに出すイベント（ミッションのある開催中のイベント、無ければ開催中の最初のイベント）。
    private var featuredEvent: EventDef? {
        let active = LiveOpsService.activeEvents(now: now)
        return active.first { !$0.missionIDs.isEmpty } ?? active.first
    }

    private var promotions: some View {
        let pass = HomePassProgress(xp: app.profile.pass.xp)
        return Group {
            promo(CGRect(x: 41, y: 170, width: 344, height: 159),
                  title: featuredEvent?.title ?? L("イベント", "Events"),
                  subtitle: featuredEvent.map { HomeFormat.remaining($0.end.timeIntervalSince(now)) } ?? L("イベント", "EVENTS"),
                  route: .events, id: "home_events", badge: HomeBadges.eventMissions(app.profile, now: now))
                .homePlaced(in: HomeLobbySlot.events)
            promo(CGRect(x: 41, y: 343, width: 344, height: 159),
                  title: LiveOpsService.passTitle, subtitle: pass.label, progress: pass.fraction,
                  route: .starPass, id: "home_starPass", badge: HomeBadges.starPass(app.profile))
                .homePlaced(in: HomeLobbySlot.starPass)
            HStack(spacing: 16) {
                rail("cart.fill", L("ストア", "Store"), .store)
                rail("scroll.fill", L("ミッション", "Missions"), .missions, badge: HomeBadges.claimableMissions(app.profile))
                rail("gift.fill", L("イベント", "Events"), .events)
            }.homePlaced(in: HomeLobbySlot.rail)
        }
    }

    /// イベント・スターパスのカード（MLBB のバナーと同じく、名前と残り時間・レベルの進み具合を小さく出す）。
    private func promo(_ source: CGRect, title: String, subtitle: String, progress: Double? = nil,
                       route: Route, id: String, badge: Int) -> some View {
        Button { app.router.push(route) } label: {
            ZStack(alignment: .bottomLeading) {
                ink
                CelestialAtlasTile(source: source).frame(height: 91)
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.48), .init(color: .clear, location: 0.59)], startPoint: .top, endPoint: .bottom))
                LinearGradient(colors: [.clear, ink.opacity(0.98)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Text(subtitle).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                        if let progress { CelestialProgressBar(value: progress, tint: .cyan, height: 4).frame(width: 64) }
                    }
                }.padding(8).padding(.trailing, 22)
                Image(systemName: "chevron.right").foregroundStyle(ice).padding(9).frame(maxWidth: .infinity, alignment: .trailing)
            }.clipShape(HomeChamfer(cut: 7))
                .overlay(HomeChamfer(cut: 7).stroke(ice.opacity(0.75), lineWidth: 0.6))
                .overlay(alignment: .topTrailing) { CelestialDot(shown: badge > 0).offset(x: -6, y: 6) }
        }.accessibilityLabel(title + " " + subtitle).accessibilityIdentifier(id)
    }

    private func rail(_ symbol: String, _ title: String, _ route: Route, badge: Int = 0) -> some View {
        Button { app.router.push(route) } label: {
            VStack(spacing: 5) {
                CelestialAtlasTile(source: railSource(symbol))
                    .mask(CelestialAtlasTile(source: railSource(symbol)).luminanceToAlpha())
                    .frame(width: 30, height: 28)
                    .overlay(alignment: .topTrailing) { CelestialDot(shown: badge > 0).offset(x: 4, y: -2) }
                Text(title).font(.system(size: 12, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(width: 53, height: 49)
        }.accessibilityLabel(title).accessibilityIdentifier("home_rail_\(String(describing: route))")
    }

    private func railSource(_ symbol: String) -> CGRect {
        switch symbol {
        case "cart.fill": CGRect(x: 60, y: 527, width: 57, height: 49)
        case "scroll.fill": CGRect(x: 181, y: 527, width: 49, height: 49)
        default: CGRect(x: 297, y: 527, width: 54, height: 49)
        }
    }

    // MARK: フレンド欄

    private var friendPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("フレンド", "Friends")).font(.system(size: 13, weight: .semibold, design: .serif))
                Spacer()
                Text("\(app.friends.friends.count)").font(.system(size: 12, design: .serif))
            }.padding(.horizontal, 17).frame(height: 38)
            Rectangle().fill(LinearGradient(colors: [.clear, ice, .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 0.7)
            ScrollView {
                VStack(spacing: 0) {
                    if app.friends.friends.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "person.2").font(.system(size: 31, weight: .ultraLight))
                            Text(L("フレンドと星の戦場へ", "Together, into the stars")).font(.system(size: 12, design: .serif))
                            Text(L("仲間を招待してパーティを組もう", "Invite friends to your party")).font(.system(size: 10))
                        }.foregroundStyle(ice).frame(maxWidth: .infinity).frame(height: 191)
                            .modifier(HomeAmbientMotion(animated: animated, travel: 1, duration: 4))
                    }
                    ForEach(app.friends.friends) { friend in
                        friendRow(friend)
                    }
                }
            }
            Button { app.router.push(.onlineLobby) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "person.badge.plus").font(.system(size: 20))
                        .overlay(alignment: .topTrailing) { CelestialDot(shown: HomeBadges.friendRequests(app.friends) > 0).offset(x: 3, y: -2) }
                    Text(L("フレンドを探す", "Find friends")).font(.system(size: 12, design: .serif))
                    Spacer()
                    Image(systemName: "chevron.right")
                }.padding(.horizontal, 14).frame(height: 36).background(ice.opacity(0.07))
            }.accessibilityIdentifier("home_friend_find")
        }
        .background(ink.opacity(0.88))
        .clipShape(HomeChamfer(cut: 8))
        .overlay(HomeChamfer(cut: 8).stroke(ice.opacity(0.6), lineWidth: 0.6))
    }

    /// フレンドの行: 名前と状態（オンライン / チーム中 / 試合中 / 練習中 / オフライン）、右端に招待のボタン。
    private func friendRow(_ friend: Friend) -> some View {
        let inMyTeam = app.online?.room.players.contains { $0.friendCode == friend.code } == true
        let status = HomeFriendStatus.of(online: app.friends.isFriendOnline(friend.code), inMyTeam: inMyTeam)
        return HStack(spacing: 9) {
            Button { app.router.push(.onlineLobby) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle").font(.system(size: 37, weight: .ultraLight))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(FriendNames.display(friend.name)).font(.system(size: 13, design: .serif)).lineLimit(1)
                        Label(status.title, systemImage: "circle.fill")
                            .font(.system(size: 9)).foregroundStyle(status.isActive ? Color.mint : ice)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.accessibilityIdentifier("home_friend_\(friend.code)")
            Button { invite(friend) } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .ultraLight)).frame(width: 30, height: 40)
            }
            .disabled(!status.canInvite)
            .opacity(status.canInvite ? 1 : 0.3)
            .accessibilityLabel(L("パーティに招待", "Invite to party"))
            .accessibilityIdentifier("home_friend_invite_\(friend.code)")
        }.padding(.horizontal, 12).frame(height: 64)
            .overlay(alignment: .bottom) { Rectangle().fill(ice.opacity(0.25)).frame(height: 0.5) }
    }

    /// 招待: パーティ（部屋）が無ければ作って招待を送り、パーティの画面を開く（MLBB と同じくチームのルームへ）。
    /// オンラインの同意がまだなら、同意の画面を兼ねるオンラインの画面だけを開く。
    private func invite(_ friend: Friend) {
        FlowFX.tap(app)
        if app.onlineAccess == .available { app.inviteToParty(friend) }
        app.router.push(.onlineLobby)
    }

    // MARK: 下段

    private var footer: some View {
        Group {
            HomeChamfer(cut: 15).fill(LinearGradient(colors: [ink.opacity(0.98), ink.opacity(0.96)], startPoint: .bottom, endPoint: .top))
                .overlay(HomeChamfer(cut: 15).stroke(HomeStyle.goldGradient.opacity(0.65), lineWidth: 0.6))
                .homePlaced(in: HomeLobbySlot.footerBand)
            HStack(spacing: 0) {
                footerLink(CGRect(x: 101, y: 739, width: 63, height: 66), L("戦闘準備", "Prepare"), .items)
                footerLink(CGRect(x: 295, y: 739, width: 66, height: 66), L("ヒーロー", "Heroes"), .heroes)
                footerLink(CGRect(x: 512, y: 739, width: 66, height: 66), L("コレクション", "Collection"), .cosmetics)
                footerLink(CGRect(x: 730, y: 739, width: 66, height: 66), L("バッグ", "Bag"), .inventory)
            }.homePlaced(in: HomeLobbySlot.footerTabs)
            Button { app.router.push(.emblems) } label: {
                Image(systemName: "sparkle").font(.system(size: 19, weight: .ultraLight)).foregroundStyle(ice).frame(width: 27, height: 60)
                    .overlay(alignment: .top) { CelestialDot(shown: HomeBadges.emblemChest(app.profile, now: now) > 0).offset(x: 8, y: 8) }
            }.accessibilityLabel(L("エンブレム", "Emblems")).accessibilityIdentifier("home_emblems").homePlaced(in: HomeLobbySlot.emblems)
            Button { app.router.push(.rankOverview) } label: {
                HStack(spacing: 9) {
                    RankEmblemView(tier: app.profile.rank.tier, size: 46)
                        .overlay(alignment: .topTrailing) { CelestialDot(shown: HomeBadges.claimableRankRewards(app.profile) > 0) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(RankService.displayName(app.profile.rank)).font(.system(size: 12, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                        RankStarsView(stars: app.profile.rank.stars, maxStars: RankService.maxStars(app.profile.rank.tier), size: 12)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .ultraLight))
                }.frame(width: 199, height: 66)
            }.accessibilityIdentifier("home_rank").homePlaced(in: HomeLobbySlot.rank)
            battleButton.homePlaced(in: HomeLobbySlot.play)
        }
    }

    private func footerLink(_ source: CGRect, _ title: String, _ route: Route) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            VStack(spacing: 3) {
                CelestialAtlasTile(source: source)
                    .mask(CelestialAtlasTile(source: source).luminanceToAlpha())
                    .frame(width: 38, height: 38)
                Text(title).font(.system(size: 13, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity).frame(height: 70)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(LinearGradient(colors: [.clear, ice.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 0.5, height: 37)
                }
                .contentShape(Rectangle())
        }.accessibilityLabel(title).accessibilityIdentifier("home_\(String(describing: route))")
    }

    private var battleButton: some View {
        Button { FlowFX.confirm(app); MatchFlowIntent.present(nil, app: app) } label: {
            ZStack {
                HomeChamfer(cut: 24).fill(Color(red: 0.12, green: 0.08, blue: 0.025))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                CelestialAtlasTile(source: CGRect(x: 1284, y: 704, width: 470, height: 135))
                    .mask(CelestialAtlasTile(source: CGRect(x: 1284, y: 704, width: 470, height: 135)).luminanceToAlpha())
                // 文字: 最後に選んだモード（MLBB と同じく「ランキング」など）。まだ選んでいなければ絵の「対戦開始」（英語版は BATTLE）
                if let title = playTitle {
                    Text(title)
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .foregroundStyle(HomeStyle.goldLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 132, height: 42)
                        .background(Color(red: 0.13, green: 0.09, blue: 0.035))
                        .offset(x: 28)
                }
                if animated { HomeSheen(period: 4).clipShape(HomeChamfer(cut: 25)) }
            }.shadow(color: Theme.gold.opacity(0.45), radius: 4)
        }.accessibilityLabel(playTitle ?? L("対戦開始", "Battle")).accessibilityIdentifier("home_play")
    }

    /// 大ボタンの文字（最後に選んだモード。無ければ nil = 絵の文字のまま。英語版は BATTLE）。
    private var playTitle: String? {
        MatchModeCategory.playTitle(app.profile.lastMatchMode) ?? (Loc.isEnglish ? "BATTLE" : nil)
    }
}

/// 赤い点（数字は出さない。MLBB 2.2.16 と同じく受け取れる物・届いた申請があるときだけ）。採用案の線の細さに合わせた小さな点。
private struct CelestialDot: View {
    let shown: Bool

    var body: some View {
        if shown {
            Circle().fill(Color.red).frame(width: 7, height: 7)
                .overlay(Circle().stroke(.white, lineWidth: 0.6))
                .accessibilityHidden(true)
        }
    }
}

/// 同じ採用原画から装飾部分だけを参照する。文字・数値はアトラスに依存しない。
private struct CelestialAtlasTile: View {
    let source: CGRect
    var body: some View {
        GeometryReader { geo in
            Image("CelestialAtlas").resizable()
                .frame(width: 1774 * geo.size.width / source.width, height: 887 * geo.size.height / source.height)
                .offset(x: -source.minX * geo.size.width / source.width, y: -source.minY * geo.size.height / source.height)
        }.clipped().accessibilityHidden(true)
    }
}

private struct CelestialFrame: View {
    let animated: Bool
    private let blue = Color(red: 0.3, green: 0.68, blue: 1)
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.75), lineWidth: 0.7)
            RoundedRectangle(cornerRadius: 12).inset(by: 3).stroke(blue.opacity(0.7), lineWidth: 0.5)
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: blue.opacity(0.1), location: 0.68), .init(color: blue, location: 0.92), .init(color: .white, location: 0.98), .init(color: .clear, location: 1)], center: .center, angle: .degrees(angle)), lineWidth: 2)
                        .shadow(color: blue, radius: 5)
                }
            }
            GeometryReader { geo in
                ForEach(0..<4) { corner in
                    let right = corner % 2 == 1
                    let bottom = corner > 1
                    CelestialAtlasTile(source: CGRect(x: 9, y: 7, width: 85, height: 35))
                        .mask(CelestialAtlasTile(source: CGRect(x: 9, y: 7, width: 85, height: 35)).luminanceToAlpha())
                        .frame(width: 49, height: 20)
                        .scaleEffect(x: right ? -1 : 1, y: bottom ? -1 : 1)
                        .position(x: right ? geo.size.width - 24 : 24, y: bottom ? geo.size.height - 10 : 10)
                }
            }
        }
    }
}

/// 粒子は固定 18 個。画面全体やプロフィールを毎フレーム再評価しない。
private struct CelestialAtmosphere: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120)
                for i in 0..<18 {
                    let x = (Double(i) * 73.1 + time * Double(2 + i % 3)).truncatingRemainder(dividingBy: size.width)
                    let y = (Double(i) * 47.3 - time * 3).truncatingRemainder(dividingBy: size.height)
                    let alpha = 0.2 + (sin(time * 0.8 + Double(i)) + 1) * 0.25
                    let rect = CGRect(x: x, y: y < 0 ? y + size.height : y, width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 2 : 1)
                    canvas.fill(Path(ellipseIn: rect), with: .color(.cyan.opacity(alpha)))
                }
            }
        }
    }
}
