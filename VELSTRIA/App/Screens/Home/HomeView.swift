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
            HomeReferenceLobby(safeArea: m.safeArea, heroID: showcaseHeroID, animated: animates, now: now, onMenu: openMenu, onPick: { pickedHeroID = $0 })
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

/// 採用コンセプトの 1774 × 887 を 1024 × 512 の座標に正規化。
/// 装飾アトラスと実データを分離し、ナビゲーションはすべて実ボタンにする。
private struct HomeReferenceLobby: View {
    let safeArea: EdgeInsets
    let heroID: String
    let animated: Bool
    let now: Date
    let onMenu: () -> Void
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var app
    @State private var friendsCollapsed = HomeDebug.startsRailCollapsed
    private let ice = Color(red: 0.65, green: 0.84, blue: 1)
    private let ink = Color(red: 0.015, green: 0.045, blue: 0.09)

    var body: some View {
        GeometryReader { geo in
            let usableWidth = geo.size.width - safeArea.leading - safeArea.trailing
            let usableHeight = geo.size.height - safeArea.top - safeArea.bottom
            let scale = min(usableWidth / 1024, usableHeight / 512)
            Image("CelestialLobby").resizable().scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height).clipped()
                .blur(radius: 20).overlay(Color.black.opacity(0.7))
            canvas
                .frame(width: 1024, height: 512)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: safeArea.leading + (usableWidth - 1024 * scale) / 2,
                        y: safeArea.top + (usableHeight - 512 * scale) / 2)
        }
        .clipped()
        .task { app.friends.start(); app.friends.refreshPresence() }
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Image("CelestialLobby").resizable().frame(width: 1024, height: 512)
                .scaleEffect(1.008)
                .modifier(HomeAmbientMotion(animated: animated, travel: 1, duration: 6))
                .overlay {
                    if animated {
                        CelestialAtmosphere().allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            // 背景はコンセプトのキービジュアル。ヒーロー一覧への入口として扱う。
            Button { app.router.push(.heroes) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(L("ヒーローを見る", "Explore heroes"))
                .homePlaced(in: CGRect(x: 228, y: 75, width: 525, height: 330))
            header
            promotions
            if !friendsCollapsed { friendPanel.homePlaced(in: CGRect(x: 773, y: 79, width: 226, height: 274)) }
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
                    avatar(app.profile.avatarHeroID, size: 49)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.profile.displayName.isEmpty ? "Player" : app.profile.displayName)
                            .font(.system(size: 14, design: .serif)).lineLimit(1)
                        HStack(spacing: 5) {
                            Text("Lv.\(app.profile.accountLevel)").font(.system(size: 12, design: .serif))
                            HomeBar(value: Double(app.profile.accountXP) / Double(max(1, FlowAccountXP.required(forLevel: app.profile.accountLevel))), tint: .cyan).frame(width: 54, height: 5)
                        }
                    }
                }
            }.accessibilityIdentifier("home_profile").homePlaced(in: CGRect(x: 26, y: 27, width: 168, height: 49))
            HStack(spacing: 10) {
                currency("dollarsign.circle.fill", HomeFormat.currency(app.profile.starlightCoin, compact: false), gold: true)
                currency("diamond.fill", "\(app.profile.totalGem)", gold: false)
                utility("envelope.fill", L("メール", "Mail"), .mail, id: "home_mail", badge: HomeBadges.unreadMail(app.profile, now: now))
                Button { friendsCollapsed.toggle() } label: { Image(systemName: "person.2.fill").font(.system(size: 23)).frame(width: 32, height: 38) }
                    .accessibilityLabel(L("フレンド欄を切り替え", "Toggle friends"))
                utility("gearshape.fill", L("設定", "Settings"), .settings, id: "home_settings")
                Button(action: onMenu) { Image(systemName: "line.3.horizontal").font(.system(size: 21)).frame(width: 32, height: 38) }
                    .accessibilityLabel(L("メニュー", "Menu")).accessibilityIdentifier("home_menu")
            }.foregroundStyle(ice).homePlaced(in: CGRect(x: 615, y: 25, width: 382, height: 38))
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

    private func currency(_ symbol: String, _ value: String, gold: Bool) -> some View {
        Button { app.router.push(.currencyStore) } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(gold ? Theme.gold : ice)
                Text(value).font(.system(size: 13, design: .serif)).lineLimit(1).minimumScaleFactor(0.65)
                Image(systemName: "plus").font(.system(size: 12, weight: .light))
            }.padding(.horizontal, 6).frame(width: 99, height: 27)
                .background(ink.opacity(0.85), in: HomeChamfer(cut: 7))
                .overlay(HomeChamfer(cut: 7).stroke(ice.opacity(0.45), lineWidth: 0.6))
        }.accessibilityLabel(L("通貨ストア", "Currency store") + " " + value)
    }

    private func utility(_ symbol: String, _ title: String, _ route: Route, id: String, badge: Int = 0) -> some View {
        Button { FlowFX.tap(app); app.router.push(route) } label: {
            Image(systemName: symbol).font(.system(size: 22)).frame(width: 32, height: 38)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { Circle().fill(.red).frame(width: 5, height: 5).overlay(Circle().stroke(.white, lineWidth: 0.5)) }
                }
        }.accessibilityLabel(title).accessibilityIdentifier(id)
    }

    private var promotions: some View {
        Group {
            promo(CGRect(x: 41, y: 170, width: 344, height: 159), title: L("星海の呼び声", "Call of the Stars"), subtitle: L("イベント", "EVENTS"), route: .events)
                .homePlaced(in: CGRect(x: 24, y: 98, width: 198, height: 91))
            promo(CGRect(x: 41, y: 343, width: 344, height: 159), title: L("月影の誓い", "Moonlit Oath"), subtitle: "STAR PASS", route: .starPass)
                .homePlaced(in: CGRect(x: 24, y: 198, width: 198, height: 91))
            HStack(spacing: 16) {
                rail("cart.fill", L("ストア", "Store"), .store)
                rail("scroll.fill", L("ミッション", "Missions"), .missions)
                rail("gift.fill", L("イベント", "Events"), .events)
            }.homePlaced(in: CGRect(x: 28, y: 306, width: 192, height: 49))
        }
    }

    private func promo(_ source: CGRect, title: String, subtitle: String, route: Route) -> some View {
        Button { app.router.push(route) } label: {
            ZStack(alignment: .bottomLeading) {
                ink
                CelestialAtlasTile(source: source).frame(height: 91)
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.48), .init(color: .clear, location: 0.59)], startPoint: .top, endPoint: .bottom))
                LinearGradient(colors: [.clear, ink.opacity(0.98)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold, design: .serif))
                    Text(subtitle).font(.system(size: 10))
                }.padding(8)
                Image(systemName: "chevron.right").foregroundStyle(ice).padding(9).frame(maxWidth: .infinity, alignment: .trailing)
            }.clipShape(HomeChamfer(cut: 7))
                .overlay(HomeChamfer(cut: 7).stroke(ice.opacity(0.75), lineWidth: 0.6))
        }.accessibilityLabel(title)
    }

    private func rail(_ symbol: String, _ title: String, _ route: Route) -> some View {
        Button { app.router.push(route) } label: {
            VStack(spacing: 5) {
                CelestialAtlasTile(source: railSource(symbol))
                    .mask(CelestialAtlasTile(source: railSource(symbol)).luminanceToAlpha())
                    .frame(width: 30, height: 28)
                Text(title).font(.system(size: 12, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(width: 53, height: 49)
        }.accessibilityLabel(title)
    }

    private func railSource(_ symbol: String) -> CGRect {
        switch symbol {
        case "cart.fill": CGRect(x: 60, y: 527, width: 57, height: 49)
        case "scroll.fill": CGRect(x: 181, y: 527, width: 49, height: 49)
        default: CGRect(x: 297, y: 527, width: 54, height: 49)
        }
    }

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
                        Button { app.router.push(.onlineLobby) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "person.crop.circle").font(.system(size: 37, weight: .ultraLight))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(FriendNames.display(friend.name)).font(.system(size: 13, design: .serif)).lineLimit(1)
                                    Label(app.friends.isFriendOnline(friend.code) ? L("オンライン", "Online") : L("オフライン", "Offline"), systemImage: "circle.fill")
                                        .font(.system(size: 9)).foregroundStyle(app.friends.isFriendOnline(friend.code) ? .mint : ice)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "plus").font(.system(size: 20, weight: .ultraLight))
                            }.padding(.horizontal, 12).frame(height: 64)
                                .overlay(alignment: .bottom) { Rectangle().fill(ice.opacity(0.25)).frame(height: 0.5) }
                        }
                    }
                }
            }
            Button { app.router.push(.onlineLobby) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "person.badge.plus").font(.system(size: 20))
                    Text(L("フレンドを探す", "Find friends")).font(.system(size: 12, design: .serif))
                    Spacer()
                    Image(systemName: "chevron.right")
                }.padding(.horizontal, 14).frame(height: 36).background(ice.opacity(0.07))
            }
        }
        .background(ink.opacity(0.88))
        .clipShape(HomeChamfer(cut: 8))
        .overlay(HomeChamfer(cut: 8).stroke(ice.opacity(0.6), lineWidth: 0.6))
    }

    private var footer: some View {
        Group {
            HomeChamfer(cut: 15).fill(LinearGradient(colors: [ink.opacity(0.98), ink.opacity(0.96)], startPoint: .bottom, endPoint: .top))
                .overlay(HomeChamfer(cut: 15).stroke(HomeStyle.goldGradient.opacity(0.65), lineWidth: 0.6))
                .homePlaced(in: CGRect(x: 10, y: 419, width: 1004, height: 81))
            HStack(spacing: 0) {
                footerLink(CGRect(x: 101, y: 739, width: 63, height: 66), L("戦闘準備", "Prepare"), .items)
                footerLink(CGRect(x: 295, y: 739, width: 66, height: 66), L("ヒーロー", "Heroes"), .heroes)
                footerLink(CGRect(x: 512, y: 739, width: 66, height: 66), L("コレクション", "Collection"), .cosmetics)
                footerLink(CGRect(x: 730, y: 739, width: 66, height: 66), L("バッグ", "Bag"), .inventory)
            }.homePlaced(in: CGRect(x: 17, y: 420, width: 487, height: 70))
            Button { app.router.push(.emblems) } label: {
                Image(systemName: "sparkle").font(.system(size: 19, weight: .ultraLight)).foregroundStyle(ice).frame(width: 27, height: 60)
            }.accessibilityLabel(L("エンブレム", "Emblems")).homePlaced(in: CGRect(x: 502, y: 427, width: 27, height: 60))
            Button { app.router.push(.rankOverview) } label: {
                HStack(spacing: 9) {
                    RankEmblemView(tier: app.profile.rank.tier, size: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(RankService.displayName(app.profile.rank)).font(.system(size: 12, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                        RankStarsView(stars: app.profile.rank.stars, maxStars: RankService.maxStars(app.profile.rank.tier), size: 12)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .ultraLight))
                }.frame(width: 199, height: 66)
            }.accessibilityIdentifier("home_rank").homePlaced(in: CGRect(x: 535, y: 424, width: 199, height: 66))
            battleButton.homePlaced(in: CGRect(x: 746, y: 414, width: 263, height: 69))
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
        }.accessibilityLabel(title)
    }

    private var battleButton: some View {
        Button { FlowFX.confirm(app); MatchFlowIntent.present(nil, app: app) } label: {
            ZStack {
                HomeChamfer(cut: 24).fill(Color(red: 0.12, green: 0.08, blue: 0.025))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                CelestialAtlasTile(source: CGRect(x: 1284, y: 704, width: 470, height: 135))
                    .mask(CelestialAtlasTile(source: CGRect(x: 1284, y: 704, width: 470, height: 135)).luminanceToAlpha())
                if Loc.isEnglish {
                    Text("BATTLE")
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .foregroundStyle(HomeStyle.goldLight)
                        .frame(width: 132, height: 42)
                        .background(Color(red: 0.13, green: 0.09, blue: 0.035))
                        .offset(x: 28)
                }
                if animated { HomeSheen(period: 4).clipShape(HomeChamfer(cut: 25)) }
            }.shadow(color: Theme.gold.opacity(0.45), radius: 4)
        }.accessibilityLabel(L("対戦開始", "Battle")).accessibilityIdentifier("home_play")
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
