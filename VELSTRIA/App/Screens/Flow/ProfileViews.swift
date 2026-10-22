import SwiftUI
import VelstriaCore

// 担当: ui-flow / outgame。UI015 プロフィール / UI016 過去の戦績 / UI005 アカウント / UI017 実績。
// MLBB 2.2.16 のプロフィール画面の作り: 左上の戻る・左のメニュー（選んだ項目は光る青い矢印の板）・青い霧の地・青灰の面。
// メニューは中身のある 3 つだけ（プロフィール・過去の戦績・アカウント。アルバム・コレクション・バトル・生放送・ソーシャルは出さない）。
// 項目は push せずにこの画面の中で切り替える（ホームのアイコン → プロフィール、設定の「アカウント連携」→ アカウント）。

/// プロフィールの画面群の色（MLBB の青灰の面・淡い青の文字）。
enum HubStyle {
    static let panel = Color(red: 0.23, green: 0.33, blue: 0.49).opacity(0.55)
    static let panelDeep = Color(red: 0.08, green: 0.13, blue: 0.23).opacity(0.85)
    /// 画面の上に重ねる面（下が透けない）。
    static let panelSolid = Color(red: 0.07, green: 0.11, blue: 0.20)
    static let row = Color(red: 0.32, green: 0.43, blue: 0.59).opacity(0.62)
    static let stroke = Color(red: 0.62, green: 0.78, blue: 0.96).opacity(0.32)
    static let text = Color(red: 0.88, green: 0.93, blue: 1.0)
    static let dim = Color(red: 0.68, green: 0.77, blue: 0.89)
    static let accent = Color(red: 0.45, green: 0.82, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.83, blue: 0.42)
}

/// 左のメニューの項目。
enum ProfileHubSection: String, CaseIterable, Hashable {
    case profile, records, account

    /// メニューの名前（MLBB の日本語クライアントと同じ）。
    var title: String {
        switch self {
        case .profile: return L("プロフィール", "Profile")
        case .records: return L("過去の戦績", "Match History")
        case .account: return L("アカウント", "Account")
        }
    }

    /// 上の題名。
    var heading: String {
        switch self {
        case .profile: return L("プロフィール", "Profile")
        case .records: return L("過去の戦績", "Match History")
        case .account: return L("アカウント設定", "Account Settings")
        }
    }

    /// UI テストの名前（戦績は前の「戦績」ボタンと同じ名前）。
    var identifier: String {
        switch self {
        case .profile: return "profile_menu_profile"
        case .records: return "profile_records"
        case .account: return "profile_account"
        }
    }
}

/// 画面の上に重ねる物（画面全体を暗くして出す）。
private enum HubOverlay: Equatable { case nameEdit, avatar, career }

/// 過去の戦績の絞り込み（MLBB の「全ての試合」の選択）。
enum RecordsFilter: String, CaseIterable, Hashable {
    case all, standard, ranked, other

    var title: String {
        switch self {
        case .all: return L("全ての試合", "All Matches")
        case .standard: return L("マッチング", "Classic")
        case .ranked: return L("ランキング", "Ranked")
        case .other: return L("その他", "Other")
        }
    }

    func includes(_ mode: MatchMode) -> Bool {
        switch self {
        case .all: return true
        case .standard: return mode == .standard
        case .ranked: return mode == .ranked
        case .other: return mode != .standard && mode != .ranked
        }
    }
}

struct ProfileHubView: View {
    @Environment(AppModel.self) private var app
    @State private var section: ProfileHubSection
    @State private var overlay: HubOverlay?
    @State private var showsNameCard = false
    @State private var recordsFilter: RecordsFilter = .all
    @State private var recordsAsList = false

    init(section: ProfileHubSection = .profile) {
        _section = State(initialValue: section)
    }

    var body: some View {
        GeometryReader { geo in
            let sidebar = min(158, max(112, geo.size.width * 0.17))
            VStack(spacing: 0) {
                topBar(sidebar: sidebar, compact: geo.size.width < 720)
                HStack(alignment: .top, spacing: 10) {
                    menu.frame(width: sidebar)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.trailing, 12)
                .padding(.bottom, 8)
            }
        }
        .background(HubBackdrop())
        .overlay { overlayContent }
        .animation(.easeInOut(duration: 0.2), value: overlay)
        .sheet(isPresented: $showsNameCard) {
            PublicNameCardView(profile: ownCard).environment(app)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: 上の列

    private func topBar(sidebar: CGFloat, compact: Bool) -> some View {
        HStack(spacing: 10) {
            HubBackButton {
                FlowFX.back(app)
                app.router.pop()
            }
            .frame(width: sidebar)
            Text(section.heading)
                .font(Celestial.title(19))
                .tracking(1.5)
                .foregroundStyle(HubStyle.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            tools(compact: compact)
        }
        .frame(height: 46)
        .padding(.trailing, 12)
    }

    @ViewBuilder private func tools(compact: Bool) -> some View {
        switch section {
        case .profile:
            HStack(spacing: 6) {
                HubToolButton(symbol: "person.text.rectangle", title: L("名刺", "Card"), id: "profile_namecard", showsTitle: !compact) {
                    FlowFX.tap(app)
                    showsNameCard = true
                }
                HubToolButton(symbol: "chart.bar.fill", title: L("データ", "Stats"), id: "profile_career", showsTitle: !compact) {
                    FlowFX.tap(app)
                    overlay = .career
                }
                HubToolButton(symbol: "trophy.fill", title: L("実績", "Awards"), id: "profile_achievements",
                              dot: HomeBadges.claimableAchievements(app.profile) > 0, showsTitle: !compact) {
                    FlowFX.tap(app)
                    app.router.push(.achievements)
                }
                HubToolButton(symbol: "gearshape.fill", title: L("設定", "Settings"), id: "profile_settings", showsTitle: !compact) {
                    FlowFX.tap(app)
                    app.router.push(.settings)
                }
            }
        case .records:
            HStack(spacing: 6) {
                RecordsFilterMenu(filter: $recordsFilter)
                Button {
                    app.audio.play(.uiTab)
                    recordsAsList.toggle()
                } label: {
                    Image(systemName: recordsAsList ? "rectangle.split.3x1.fill" : "list.bullet")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(HubStyle.text)
                        .frame(width: 36, height: 32)
                        .background(Rectangle().fill(HubStyle.row))
                        .overlay(Rectangle().stroke(HubStyle.accent.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recordsAsList ? L("カードで表示", "Show as cards") : L("一覧で表示", "Show as list"))
                .accessibilityIdentifier("records_layout")
                HubToolButton(symbol: "play.rectangle.fill", title: L("リプレイ", "Replays"), id: "records_replays") {
                    FlowFX.tap(app)
                    app.router.push(.replays)
                }
            }
        case .account:
            EmptyView()
        }
    }

    // MARK: 左のメニュー

    private var menu: some View {
        VStack(spacing: 2) {
            ForEach(ProfileHubSection.allCases, id: \.self) { s in
                HubMenuItem(title: s.title, selected: section == s, dot: dot(s)) {
                    guard section != s else { return }
                    app.audio.play(.uiTab)
                    withAnimation(.easeInOut(duration: 0.18)) { section = s }
                }
                .accessibilityIdentifier(s.identifier)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    /// 赤い点: 受け取れる実績（プロフィール）・ほかの端末で取り出せないアカウント（アカウント。MLBB と同じ）。
    private func dot(_ s: ProfileHubSection) -> Bool {
        switch s {
        case .profile: return HomeBadges.claimableAchievements(app.profile) > 0
        case .records: return false
        case .account: return app.syncsCloudRank && !app.profile.account.isRecoverable
        }
    }

    // MARK: 中身

    @ViewBuilder private var content: some View {
        switch section {
        case .profile:
            ProfileOverviewPane(open: { overlay = $0 })
        case .records:
            RecordsPane(filter: recordsFilter, asList: recordsAsList)
        case .account:
            AccountPane()
        }
    }

    @ViewBuilder private var overlayContent: some View {
        switch overlay {
        case .nameEdit?:
            NameEditOverlay(initial: app.profile.displayName) { newName in
                if let newName {
                    app.profile.displayName = newName
                    FlowFX.confirm(app)
                    app.showToast(L("名前を変更しました", "Name updated"))
                }
                overlay = nil
            }
            .transition(.opacity)
        case .avatar?:
            AvatarPickerOverlay { overlay = nil }
                .transition(.opacity)
        case .career?:
            CareerDataOverlay { overlay = nil }
                .transition(.opacity)
        case nil:
            EmptyView()
        }
    }

    /// 自分の名刺（他の人が見るのと同じ形。ランクは端末の値）。
    private var ownCard: PublicProfile {
        let p = app.profile
        let heroes = DraftShowcase.favorites(p, roster: app.master.heroes.map(\.heroID), limit: 3).map { id -> PublicHeroStat in
            let c = p.career.perHero[id] ?? HeroCareer()
            return PublicHeroStat(heroID: id, matches: c.matches, wins: min(c.wins, c.matches))
        }
        let r = p.rank
        return PublicProfile(code: p.friendCode, name: app.onlineName, avatar: p.avatarHeroID, frame: p.equippedAvatarFrame,
                             level: max(1, p.accountLevel), rank: PublicRank(r),
                             seasonBest: PublicRank(tier: max(r.seasonHighestTier, r.tier).rawValue, division: 0, stars: 0),
                             highest: PublicRank(tier: r.highestTier.rawValue, division: 0, stars: r.highestMythicStars),
                             country: p.countryCode, heroes: heroes, matches: p.career.matches, wins: min(p.career.wins, p.career.matches),
                             seasonWins: r.seasonWins, seasonLosses: r.seasonLosses, updatedAt: Date(), lastSeen: Date())
    }
}

// MARK: - 部品

/// 青い霧の地（MLBB のプロフィールの空の色）。季節のキービジュアルをぼかした上に青を重ねる。
struct HubBackdrop: View {
    var body: some View {
        ZStack {
            CelestialBackdrop()
            LinearGradient(colors: [Color(red: 0.22, green: 0.36, blue: 0.58).opacity(0.62),
                                    Color(red: 0.10, green: 0.18, blue: 0.34).opacity(0.70),
                                    Color(red: 0.05, green: 0.09, blue: 0.18).opacity(0.80)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}

/// 面（四角い青灰の板と細い縁）。
struct HubPanel: View {
    var fill: Color = HubStyle.panel

    var body: some View {
        Rectangle().fill(fill)
            .overlay(Rectangle().stroke(HubStyle.stroke, lineWidth: 0.8))
    }
}

/// 左上の戻る（右辺を斜めに落とした暗い板と、曲がった矢印）。
struct HubBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [.white, HubStyle.accent], startPoint: .top, endPoint: .bottom))
                .shadow(color: HubStyle.accent.opacity(0.6), radius: 4)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(HubBackPlate().fill(LinearGradient(colors: [Color(red: 0.10, green: 0.17, blue: 0.30).opacity(0.95),
                                                                       Color(red: 0.04, green: 0.08, blue: 0.16).opacity(0.95)],
                                                              startPoint: .top, endPoint: .bottom)))
                .overlay(HubBackPlate().stroke(HubStyle.stroke, lineWidth: 0.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("戻る", "Back"))
        .accessibilityIdentifier("nav_back")
    }
}

/// 右辺を斜めに落とした板（戻る）。
struct HubBackPlate: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.height * 0.5, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 左のメニューの選んだ項目の板（右端が矢印の、光る青い板）。
struct HubTabPlate: Shape {
    func path(in r: CGRect) -> Path {
        let tip = r.height * 0.38
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + 3))
        p.addLine(to: CGPoint(x: r.maxX - tip, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - tip, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 3))
        p.closeSubpath()
        return p
    }
}

/// 左のメニューの 1 項目。
struct HubMenuItem: View {
    let title: String
    let selected: Bool
    var dot = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: selected ? .bold : .semibold, design: .serif))
                .foregroundStyle(selected ? Color.white : HubStyle.dim)
                .shadow(color: selected ? Color(red: 0.02, green: 0.20, blue: 0.48) : .clear, radius: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background {
                    if selected {
                        HubTabPlate()
                            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.44, blue: 0.80).opacity(0.95),
                                                          Color(red: 0.45, green: 0.84, blue: 1.0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .overlay(HubTabPlate().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                            .shadow(color: HubStyle.accent.opacity(0.8), radius: 8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white, lineWidth: 0.6))
                            .offset(x: -16, y: 9)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 上の列の右の小さなボタン（MLBB の「設定」の枠）。
struct HubToolButton: View {
    let symbol: String
    let title: String
    let id: String
    var dot = false
    /// 文字も出す（狭い画面はアイコンだけ。読み上げは文字のまま）。
    var showsTitle = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                if showsTitle {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(minWidth: showsTitle ? nil : 22)
            .foregroundStyle(HubStyle.text)
            .padding(.horizontal, 9)
            .frame(minHeight: 32)
            .background(Rectangle().fill(LinearGradient(colors: [Color(red: 0.24, green: 0.40, blue: 0.62).opacity(0.9),
                                                                 Color(red: 0.14, green: 0.25, blue: 0.42).opacity(0.9)],
                                                        startPoint: .top, endPoint: .bottom)))
            .overlay(Rectangle().stroke(HubStyle.accent.opacity(0.55), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if dot {
                    Circle().fill(Color.red).frame(width: 7, height: 7).overlay(Circle().stroke(.white, lineWidth: 0.6)).offset(x: 3, y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

/// 細い区切り線。
struct HubDivider: View {
    var body: some View {
        Rectangle().fill(HubStyle.stroke).frame(height: 0.8)
    }
}

// MARK: - プロフィール（MLBB: 左の面に名前・ID・レベル・国、段位章と実績の章、右に写真の面）

private struct ProfileOverviewPane: View {
    let open: (HubOverlay) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 10) {
                mainPanel(compact: geo.size.height < 340)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                photoWall(height: geo.size.height)
                    .frame(width: min(300, geo.size.width * 0.36))
            }
        }
    }

    // MARK: 左の面

    private func mainPanel(compact: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                identity
                infoLines
                HubDivider()
                medals(compact: compact)
                heroLine
                HubDivider()
                footer
            }
            .padding(compact ? 9 : 12)
        }
        .background(HubPanel())
    }

    private var displayName: String {
        app.profile.displayName.isEmpty ? L("プレイヤー", "Player") : app.profile.displayName
    }

    private var identity: some View {
        let p = app.profile
        return HStack(alignment: .top, spacing: 10) {
            Button {
                FlowFX.tap(app)
                open(.avatar)
            } label: {
                HeroPortraitView(heroID: p.avatarHeroID, size: 60, showsRole: false)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("アイコンを変更", "Change icon"))
            .accessibilityIdentifier("profile_avatar")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Button {
                        FlowFX.tap(app)
                        open(.nameEdit)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(HubStyle.accent)
                            .frame(width: 34, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("名前を変更", "Edit name"))
                    .accessibilityIdentifier("profile_edit_name")
                }
                // ID はフレンドコード（中継に登録を済ませるまでは見せない。知った他人に先に使われないように）
                Text("ID: " + (p.inboxRegistered ? FriendCode.display(p.friendCode) : L("オンラインに同意すると発行", "Issued after online consent")))
                    .font(Theme.mono(10))
                    .foregroundStyle(HubStyle.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    levelBadge
                    CountryFlagBadge(code: p.countryCode, size: 16)
                }
            }
            Spacer(minLength: 4)
            stats
        }
    }

    private var levelBadge: some View {
        let p = app.profile
        return HStack(spacing: 4) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [HomeStyle.goldLight, HubStyle.accent], startPoint: .top, endPoint: .bottom))
            Text("\(p.accountLevel)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
            CelestialProgressBar(value: Double(p.accountXP) / Double(max(1, FlowAccountXP.required(forLevel: p.accountLevel))),
                                 tint: HubStyle.accent, height: 4)
                .frame(width: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("レベル \(p.accountLevel)", "Level \(p.accountLevel)"))
    }

    /// 右上の 3 つの数（MLBB の人気度・ギフト・いいねの位置。Velstria にある物: ログイン日数・フレンド・実績）。
    private var stats: some View {
        let p = app.profile
        let unlocked = p.achievements.values.filter { $0.unlockedAt != nil }.count
        return HStack(spacing: 14) {
            stat("flame.fill", "\(p.totalLoginDays)", L("ログイン日数", "Login days"))
            stat("person.2.fill", "\(p.friends.count)", L("フレンド", "Friends"))
            stat("hand.thumbsup.fill", "\(unlocked)", L("実績", "Achievements"))
        }
        .padding(.top, 2)
    }

    private func stat(_ symbol: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, HubStyle.dim], startPoint: .top, endPoint: .bottom))
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(minWidth: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    private var infoLines: some View {
        let p = app.profile
        let country = p.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
        return VStack(alignment: .leading, spacing: 4) {
            infoLine("mappin.and.ellipse", country ?? L("データなし", "No data"))
            infoLine("calendar", L("開始日 ", "Since ") + FlowText.date(p.createdAt, time: false))
        }
    }

    private func infoLine(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(HubStyle.dim).frame(width: 18)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(HubStyle.text).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: 章（段位 3 つ・実績 3 つ）

    private func medals(compact: Bool) -> some View {
        let r = app.profile.rank
        let seasonBest = max(r.seasonHighestTier, r.tier)
        let latest = latestAchievements
        return VStack(spacing: compact ? 3 : 6) {
            Button {
                FlowFX.tap(app)
                app.router.push(.rankOverview)
            } label: {
                HStack(alignment: .top, spacing: 4) {
                    rankMedal(r.tier, title: L("現在ランク", "Current Rank"), sub: RankInlineText.current(r), size: compact ? 34 : 44)
                    rankMedal(r.highestTier, title: L("最高ランク", "Highest Rank"),
                              sub: r.highestTier == .mythic ? RankService.mythicName(stars: r.highestMythicStars) : RankService.tierName(r.highestTier),
                              size: compact ? 34 : 44)
                    rankMedal(seasonBest, title: L("今シーズン最高", "Season Best"), sub: RankService.tierName(seasonBest), size: compact ? 34 : 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_rank")
            Button {
                FlowFX.tap(app)
                app.router.push(.achievements)
            } label: {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        achievementMedal(i < latest.count ? latest[i] : nil, size: compact ? 30 : 40)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_badges")
        }
    }

    private func rankMedal(_ tier: RankTier, title: String, sub: String, size: CGFloat) -> some View {
        VStack(spacing: 2) {
            RankCrest(tier: tier, size: size)
                .shadow(color: FlowText.tierColors(tier)[0].opacity(0.5), radius: 6)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(HubStyle.text).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 9, weight: .medium)).foregroundStyle(HubStyle.dim).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// 最近達成した実績（新しい順に 3 つ）。
    private var latestAchievements: [AchievementDef] {
        let a = app.profile.achievements
        return LiveOpsService.achievements
            .filter { a[$0.id]?.unlockedAt != nil }
            .sorted { (a[$0.id]?.unlockedAt ?? .distantPast) > (a[$1.id]?.unlockedAt ?? .distantPast) }
            .prefix(3)
            .map { $0 }
    }

    private func achievementMedal(_ def: AchievementDef?, size: CGFloat) -> some View {
        VStack(spacing: 2) {
            ZStack {
                HexagonShape()
                    .fill(def != nil ? AnyShapeStyle(LinearGradient(colors: [HomeStyle.goldLight, Color(red: 0.62, green: 0.38, blue: 0.10)],
                                                                    startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.white.opacity(0.08)))
                HexagonShape().stroke(def != nil ? Color.white.opacity(0.8) : HubStyle.stroke, lineWidth: 1)
                Image(systemName: def != nil ? "trophy.fill" : "questionmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(def != nil ? Color(red: 0.30, green: 0.16, blue: 0.02) : HubStyle.dim)
            }
            .frame(width: size, height: size)
            Text(def?.title ?? L("未達成", "Locked"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(def != nil ? HubStyle.text : HubStyle.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: よく使うヒーローと所持

    private var heroLine: some View {
        let p = app.profile
        let favorites = DraftShowcase.favorites(p, roster: app.master.heroes.map(\.heroID), limit: 4)
        let owned = p.ownedHeroIDs.filter(HeroRoster.isActive).count
        return HStack(spacing: 6) {
            ForEach(favorites, id: \.self) { id in
                HeroPortraitView(heroID: id, size: 30, showsRole: false, face: true)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HubStyle.accent.opacity(0.7), lineWidth: 1))
            }
            if favorites.isEmpty {
                Text(L("まだ試合の記録がありません", "No matches yet")).font(.system(size: 11)).foregroundStyle(HubStyle.dim)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill").font(.system(size: 11))
                Text(L("所持ヒーロー \(owned)/\(app.master.heroes.count)", "Heroes \(owned)/\(app.master.heroes.count)"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(HubStyle.text)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 24)
            .background(HubCollectorPlate().fill(LinearGradient(colors: [Color(red: 0.22, green: 0.42, blue: 0.75).opacity(0.9), .clear],
                                                                startPoint: .leading, endPoint: .trailing)))
        }
    }

    // MARK: 下の列

    private var footer: some View {
        let p = app.profile
        let c = p.career
        let recent = Array(p.recentPlayers.prefix(3))
        return HStack(alignment: .center, spacing: 8) {
            Text(L("最近の対戦", "Recent")).font(.system(size: 12, weight: .semibold)).foregroundStyle(HubStyle.dim)
            if recent.isEmpty {
                Text("—").foregroundStyle(HubStyle.dim)
            }
            ForEach(recent) { rp in
                Text(String(PlayerNameRules.shown(rp.name).prefix(1)))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 4).fill(tint(rp.code)))
                    .accessibilityLabel(PlayerNameRules.shown(rp.name))
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                footerStat(L("対戦回数：", "Matches: "), "\(c.matches)")
                footerStat(L("勝率：", "Win rate: "), c.matches > 0 ? "\(Int((Double(c.wins) / Double(c.matches) * 100).rounded()))%" : "—")
            }
        }
    }

    /// 一緒に遊んだ人の色（コードから決まる。起動ごとに変わらない）。
    private func tint(_ code: String) -> Color {
        let sum = code.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.5, brightness: 0.55)
    }

    private func footerStat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(HubStyle.dim)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 右の面（MLBB の写真の面: 大きな 1 枚と小さな 3 枚。Velstria はアイコンのヒーローの絵と、よく使うヒーロー）

    private func photoWall(height: CGFloat) -> some View {
        let favorites = DraftShowcase.favorites(app.profile, roster: app.master.heroes.map(\.heroID), limit: 3)
        let slot = max(56, min(96, height * 0.26))
        return VStack(spacing: 6) {
            Button {
                FlowFX.tap(app)
                open(.avatar)
            } label: {
                ZStack(alignment: .bottom) {
                    HubPanel()
                    HubHeroArt(heroID: app.profile.avatarHeroID)
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 12))
                        Text(L("タップしてアイコンを変更", "Tap to change your icon")).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(HubStyle.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(LinearGradient(colors: [.clear, Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                }
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_art")
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    favoriteSlot(i < favorites.count ? favorites[i] : nil)
                }
            }
            .frame(height: slot)
        }
    }

    private func favoriteSlot(_ heroID: String?) -> some View {
        ZStack(alignment: .bottom) {
            HubPanel()
            if let heroID {
                HubHeroArt(heroID: heroID, face: true)
                let c = app.profile.career.perHero[heroID] ?? HeroCareer()
                Text(L("\(c.matches) 試合", "\(c.matches) games"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55))
            } else {
                // MLBB の空きの枠（＋）
                ZStack {
                    Circle().stroke(HubStyle.stroke, lineWidth: 3).frame(width: 34, height: 34)
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(HubStyle.stroke)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

/// 所持の帯の左端（MLBB の「見習いコレクター」の帯の矢羽）。
private struct HubCollectorPlate: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.height * 0.4, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// ヒーローの絵を枠いっぱいに（はみ出しは切る。カード絵が無ければ立ち絵）。
struct HubHeroArt: View {
    let heroID: String
    var face = false

    var body: some View {
        Color.clear
            .overlay {
                if let image = (face ? PortraitArt.face(heroID) : PortraitArt.card(heroID)) ?? PortraitArt.hero(heroID) {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hue: Theme.heroHue(heroID), saturation: 0.6, brightness: 0.7),
                                            Color(hue: Theme.heroHue(heroID), saturation: 0.8, brightness: 0.25)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// 今のランクの短い名前（「エピック II ★3」。ミシックは段階名と星）。
enum RankInlineText {
    static func current(_ r: RankState) -> String {
        if r.tier == .mythic { return RankService.mythicName(stars: r.stars) + " ★\(r.stars)" }
        return "\(RankService.tierName(r.tier)) \(RankService.roman(max(1, r.division))) ★\(r.stars)"
    }

    /// 戦績のカードの「IV★0」（ミシックは「★12」）。
    static func short(_ r: PublicRank) -> String {
        if PublicRankText.tier(r) == .mythic { return "★\(r.stars)" }
        return "\(RankService.roman(max(1, r.division)))★\(r.stars)"
    }
}

// MARK: - アイコンの変更・対戦データ（画面全体に重ねる）

/// アイコンの変更（所持ヒーローから選ぶ）。
private struct AvatarPickerOverlay: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let owned = app.master.heroes.filter { app.owns(heroID: $0.heroID) }
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 10) {
                HStack {
                    Text(L("アイコンを変更", "Change Icon")).font(Celestial.heading(17)).foregroundStyle(HubStyle.text)
                    Spacer()
                    FlowCloseButton(identifier: "profile_avatar_close", action: onClose)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 8) {
                        ForEach(owned) { h in
                            Button {
                                FlowFX.tap(app)
                                app.profile.avatarHeroID = h.heroID
                            } label: {
                                HeroGridCell(hero: h, selected: app.profile.avatarHeroID == h.heroID, size: 52)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile_avatar_\(h.heroID)")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(14)
            .frame(maxWidth: 620, maxHeight: 330)
            .background(HubPanel(fill: HubStyle.panelSolid))
            .padding(12)
        }
    }
}

/// 対戦データ（今シーズンのランク戦・全シーズンの通算。MLBB 2.2.16 の切り替え）。
private struct CareerDataOverlay: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @State private var scope: Scope = .season

    enum Scope: Hashable { case season, all }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(L("対戦データ", "Match Data")).font(Celestial.heading(17)).foregroundStyle(HubStyle.text)
                    CelestialTabs(options: [
                        CelestialTab(value: Scope.season, title: L("今シーズン", "This Season"), symbol: nil, identifier: "profile_scope_season"),
                        CelestialTab(value: Scope.all, title: L("全シーズン", "All Seasons"), symbol: nil, identifier: "profile_scope_all"),
                    ], selection: $scope, fills: false, onChange: { _ in app.audio.play(.uiTab) })
                    Spacer()
                    FlowCloseButton(identifier: "profile_career_close", action: onClose)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        grid
                        topHeroes
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 640, maxHeight: 340)
            .background(HubPanel(fill: HubStyle.panelSolid))
            .padding(12)
        }
    }

    @ViewBuilder private var grid: some View {
        let c = app.profile.career
        let r = app.profile.rank
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        if scope == .season {
            // 今シーズンのランク戦（MLBB の名刺の ID カードと同じ: 試合数・勝率・今シーズンの最高ランク）
            let games = r.seasonWins + r.seasonLosses
            LazyVGrid(columns: columns, spacing: 8) {
                FlowStatCell(title: L("ランク戦", "Ranked"), value: "\(games)")
                FlowStatCell(title: L("勝率", "Win rate"), value: games > 0 ? "\(r.seasonWins * 100 / games)%" : "—",
                             tint: games > 0 && r.seasonWins * 2 >= games ? Theme.success : Theme.textPrimary)
                FlowStatCell(title: L("勝利", "Wins"), value: "\(r.seasonWins)", tint: Theme.success)
                FlowStatCell(title: L("今シーズンの最高", "Season best"), value: RankService.tierName(max(r.seasonHighestTier, r.tier)), tint: Theme.gold)
            }
        } else {
            let winRate = c.matches > 0 ? Double(c.wins) / Double(c.matches) : 0
            let kda = Double(c.kills + c.assists) / Double(max(1, c.deaths))
            LazyVGrid(columns: columns, spacing: 8) {
                FlowStatCell(title: L("試合", "Matches"), value: "\(c.matches)")
                FlowStatCell(title: L("勝率", "Win rate"), value: c.matches > 0 ? "\(Int((winRate * 100).rounded()))%" : "—",
                             tint: winRate >= 0.5 ? Theme.success : Theme.textPrimary)
                FlowStatCell(title: "KDA", value: c.matches > 0 ? String(format: "%.2f", kda) : "—", tint: Theme.cyan)
                FlowStatCell(title: "MVP", value: "\(c.mvps)", tint: Theme.gold)
                FlowStatCell(title: L("最長連勝", "Best streak"), value: "\(c.longestWinStreak)")
                FlowStatCell(title: L("現在の連勝", "Current streak"), value: "\(c.currentWinStreak)")
                FlowStatCell(title: L("ペンタキル", "Penta kills"), value: "\(c.pentaKills)")
                FlowStatCell(title: L("総ダメージ", "Total damage"), value: FlowText.compactNumber(c.totalDamage))
            }
        }
    }

    private var topHeroes: some View {
        let per = app.profile.career.perHero
        let top = per.keys.sorted { a, b in
            let ma = per[a]?.matches ?? 0, mb = per[b]?.matches ?? 0
            return ma == mb ? a < b : ma > mb
        }
        .prefix(3)
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: L("よく使うヒーロー", "Most Played"), symbol: "flame.fill")
            if top.isEmpty {
                Text(L("まだ試合の記録がありません。対戦してみましょう！", "No matches yet — jump into a battle!"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(top), id: \.self) { id in
                        let hc = per[id] ?? HeroCareer()
                        HStack(spacing: 8) {
                            HeroPortraitView(heroID: id, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.master.hero(id).map { MasterText.hero($0) } ?? id)
                                    .font(Theme.heading(12)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                                Text(L("\(hc.matches) 試合 · 勝率 \(hc.matches > 0 ? hc.wins * 100 / hc.matches : 0)%",
                                       "\(hc.matches) games · \(hc.matches > 0 ? hc.wins * 100 / hc.matches : 0)% WR"))
                                    .font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(HubPanel())
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// 名前変更のオーバーレイ（ソフトウェアキーボードに隠れないよう上寄せ）。
private struct NameEditOverlay: View {
    let initial: String
    /// nil = キャンセル。
    let onDone: (String?) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private var issue: PlayerNameRules.Issue? { PlayerNameRules.validate(name) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { onDone(nil) }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("プレイヤー名の変更", "Change Player Name"))
                    .font(Theme.heading(17))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    TextField(L("プレイヤー名", "Player name"), text: $name)
                        .font(Theme.heading(17))
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { if issue == nil { onDone(PlayerNameRules.normalized(name)) } }
                        .accessibilityIdentifier("profile_name_field")
                    Text("\(PlayerNameRules.normalized(name).count)/\(PlayerNameRules.maxLength)")
                        .font(Theme.mono(12))
                        .foregroundStyle(issue == .tooLong ? Theme.danger : Theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .glass(cornerRadius: 12, tint: Theme.cyan, highlighted: true)
                if let issue {
                    Text(PlayerNameRules.message(issue)).font(Theme.body(12)).foregroundStyle(Theme.danger)
                }
                HStack {
                    if FeatureFlags.lanMatch {
                        // 名前はオンラインで他のプレイヤーに見えるので、ルールへのリンクを置く（ガイドライン 1.2）
                        Link(L("名前のルール", "Name rules"), destination: FeatureFlags.communityGuidelinesURL)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.cyan)
                            .accessibilityIdentifier("profile_name_guidelines")
                    }
                    Spacer()
                    Button(L("キャンセル", "Cancel")) { onDone(nil) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("profile_name_cancel")
                    Button(L("保存", "Save")) { onDone(PlayerNameRules.normalized(name)) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(issue != nil)
                        .opacity(issue == nil ? 1 : 0.5)
                        .accessibilityIdentifier("profile_name_save")
                }
            }
            .padding(18)
            .frame(maxWidth: 460)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelStroke))
            .padding(.top, 16)
        }
        .onAppear {
            name = initial
            focused = true
        }
    }
}

// MARK: - UI016 過去の戦績（MLBB: 縦長のカードを横に並べる。勝敗・Lv・モード、ヒーローの絵、段位の前後、装備 6 つ、K/D/A、勲章、日時）

/// 絞り込み（上の列の「全ての試合 ▾」）。
struct RecordsFilterMenu: View {
    @Binding var filter: RecordsFilter

    var body: some View {
        Menu {
            ForEach(RecordsFilter.allCases, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    if filter == f {
                        Label(f.title, systemImage: "checkmark")
                    } else {
                        Text(f.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 0) {
                Text(filter.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HubStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 92, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 32)
                    .background(Rectangle().fill(Color(red: 0.24, green: 0.42, blue: 0.66)))
            }
            .frame(height: 32)
            .background(Rectangle().fill(Color(red: 0.06, green: 0.10, blue: 0.18).opacity(0.9)))
            .overlay(Rectangle().stroke(HubStyle.stroke, lineWidth: 0.8))
        }
        .accessibilityLabel(L("絞り込み: \(filter.title)", "Filter: \(filter.title)"))
        .accessibilityIdentifier("records_filter")
    }
}

struct RecordsPane: View {
    let filter: RecordsFilter
    let asList: Bool
    @Environment(AppModel.self) private var app
    @State private var selected: MatchRecord?
    @State private var pendingLaunch: BattleLaunch?

    private var records: [MatchRecord] {
        app.profile.matchHistory.filter { filter.includes($0.mode) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let list = records
        Group {
            if list.isEmpty {
                EmptyStateView(symbol: "list.bullet.rectangle", title: L("戦績はまだありません", "No matches yet"),
                               message: L("対戦を終えると、直近 50 試合の記録がここに残ります。", "Your 50 most recent matches will be listed here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HubPanel())
            } else if asList {
                listView(list)
            } else {
                cards(list)
            }
        }
        .sheet(item: $selected, onDismiss: startPendingReplay) { r in
            RecordDetailSheet(record: r, replay: replayMeta(for: r)) { launch in
                pendingLaunch = launch
                selected = nil
            }
            .environment(app)
        }
    }

    private func cards(_ list: [MatchRecord]) -> some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = min(210, max(124, height * 0.46))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        Button {
                            FlowFX.tap(app)
                            selected = r
                        } label: {
                            RecordCard(record: r, hasReplay: replayMeta(for: r) != nil)
                                .frame(width: width, height: height)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("records_row_\(i)")
                    }
                }
            }
        }
    }

    private func listView(_ list: [MatchRecord]) -> some View {
        VStack(spacing: 8) {
            summaryStrip(list)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        Button {
                            FlowFX.tap(app)
                            selected = r
                        } label: {
                            RecordRow(record: r, hasReplay: replayMeta(for: r) != nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("records_row_\(i)")
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func summaryStrip(_ list: [MatchRecord]) -> some View {
        let wins = list.filter { $0.won == true }.count
        let decided = list.filter { $0.won != nil }.count
        let k = list.reduce(0) { $0 + $1.kills }, d = list.reduce(0) { $0 + $1.deaths }, a = list.reduce(0) { $0 + $1.assists }
        let mvps = list.filter(\.isMVP).count
        return HStack(spacing: 6) {
            miniStat(L("試合", "Games"), "\(list.count)")
            miniStat(L("勝率", "Win%"), decided > 0 ? "\(wins * 100 / decided)%" : "—")
            miniStat("KDA", list.isEmpty ? "—" : String(format: "%.1f", Double(k + a) / Double(max(1, d))))
            miniStat("MVP", "\(mvps)")
            Spacer(minLength: 0)
        }
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(Theme.mono(14)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .frame(minWidth: 56, minHeight: 40)
        .padding(.horizontal, 4)
        .background(HubPanel())
        .accessibilityElement(children: .combine)
    }

    private func replayMeta(for r: MatchRecord) -> ReplayMeta? {
        guard let id = r.replayID else { return nil }
        return app.profile.replays.first { $0.id == id }
    }

    /// シートが閉じ終わってから戦闘を開始する（表示の重なりを避ける）。
    private func startPendingReplay() {
        guard let launch = pendingLaunch else { return }
        pendingLaunch = nil
        app.startBattle(launch)
    }
}

/// 戦績の 1 枚（MLBB の縦長のカード）。
private struct RecordCard: View {
    let record: MatchRecord
    let hasReplay: Bool

    private var won: Bool { record.won == true }

    var body: some View {
        VStack(spacing: 0) {
            header
            art
            footer
        }
        .background(Rectangle().fill(HubStyle.panelDeep))
        .overlay(Rectangle().stroke(won ? HubStyle.gold.opacity(0.75) : HubStyle.stroke, lineWidth: 1))
        .clipped()
        .accessibilityElement(children: .combine)
    }

    // MARK: 上: 勝敗・Lv・モード

    private var resultText: String {
        record.won == true ? L("勝利", "Victory") : (record.won == false ? L("敗北", "Defeat") : L("終了", "Ended"))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(resultText)
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .italic()
                    .foregroundStyle(won ? AnyShapeStyle(LinearGradient(colors: [.white, HubStyle.gold], startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(Color.white))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let level = record.summary?.humanPlayer?.level {
                    Text("Lv \(level)").font(.system(size: 11, weight: .semibold)).foregroundStyle(HubStyle.text)
                }
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: modeSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HubStyle.accent)
                    .frame(width: 22, height: 18)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                Text(FlowText.mode(record.mode))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HubStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(LinearGradient(colors: won ? [HubStyle.gold.opacity(0.38), Color(red: 0.20, green: 0.28, blue: 0.42).opacity(0.9)]
                                               : [Color(red: 0.34, green: 0.44, blue: 0.60).opacity(0.9), Color(red: 0.20, green: 0.28, blue: 0.42).opacity(0.9)],
                                   startPoint: .leading, endPoint: .trailing))
    }

    private var modeSymbol: String {
        switch record.mode {
        case .ranked: return "crown.fill"
        case .standard: return "person.3.fill"
        default: return "gamecontroller.fill"
        }
    }

    // MARK: 中: ヒーローの絵（右上に評価、リプレイがあれば左上に印）

    private var art: some View {
        HubHeroArt(heroID: record.heroID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                GradeBadge(grade: record.grade, size: 22).padding(6)
            }
            .overlay(alignment: .topLeading) {
                if hasReplay {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, HubStyle.panelDeep], startPoint: .top, endPoint: .bottom).frame(height: 26)
            }
    }

    // MARK: 下: 段位の前後・装備・K/D/A・勲章・日時

    private var footer: some View {
        VStack(spacing: 5) {
            rankLine
            items
            kda
            MatchMedalView(medal: medal, size: 30)
            Text(Self.dateText(record.date))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(HubStyle.dim)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var rankLine: some View {
        if let b = record.rankBefore, let a = record.rankAfter {
            HStack(spacing: 3) {
                RankCrest(tier: PublicRankText.tier(b), size: 16)
                Text(RankInlineText.short(b))
                Text("»").foregroundStyle(HubStyle.accent)
                RankCrest(tier: PublicRankText.tier(a), size: 16)
                Text(RankInlineText.short(a))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HubStyle.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            Text(record.mode == .standard || record.mode == .ranked ? "AI · " + FlowText.difficulty(record.difficulty)
                                                                     : FlowText.duration(record.duration))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HubStyle.dim)
                .lineLimit(1)
                .frame(height: 16)
        }
    }

    private var items: some View {
        HStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { i in
                RecordItemSlot(itemID: i < record.items.count ? record.items[i] : nil)
            }
        }
    }

    private var kda: some View {
        HStack(spacing: 8) {
            kdaCell("xmark", record.kills, L("キル", "Kills"))
            kdaCell("heart.slash.fill", record.deaths, L("デス", "Deaths"))
            kdaCell("hand.thumbsup.fill", record.assists, L("アシスト", "Assists"))
        }
    }

    private func kdaCell(_ symbol: String, _ value: Int, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(HubStyle.dim)
            Text("\(value)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    /// 勲章（試合の集計があれば評価点から。旧版の記録は MVP の印だけ）。
    private var medal: MatchMedal? {
        if let s = record.summary, let human = s.humanPlayer { return MatchMedal.result(for: human, in: s).medal }
        guard record.isMVP else { return nil }
        return record.won == false ? .mvpLoss : .mvp
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()

    static func dateText(_ d: Date) -> String { formatter.string(from: d) }
}

/// 装備の 1 枠（丸。空きは暗い丸）。
private struct RecordItemSlot: View {
    let itemID: String?

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45))
            if let itemID, let image = PortraitArt.item(itemID) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(Circle())
            }
        }
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 24)
    }
}

private struct RecordRow: View {
    let record: MatchRecord
    let hasReplay: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let r = record
        let color: Color = r.won == true ? Theme.success : (r.won == false ? Theme.danger : Theme.textSecondary)
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: r.won == true ? "crown.fill" : (r.won == false ? "xmark.shield.fill" : "minus.circle"))
                    .font(.system(size: 14, weight: .bold))
                Text(r.won == true ? L("勝利", "WIN") : (r.won == false ? L("敗北", "LOSS") : "—"))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(color)
            .frame(width: 44)
            HeroPortraitView(heroID: r.heroID, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.master.hero(r.heroID).map { MasterText.hero($0) } ?? r.heroID)
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(FlowText.mode(r.mode))" + (r.mode == .standard || r.mode == .ranked ? " · \(FlowText.difficulty(r.difficulty))" : ""))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 110, alignment: .leading)
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(FlowText.kda(r.kills, r.deaths, r.assists)).font(Theme.mono(13)).foregroundStyle(Theme.textPrimary)
                Text("CS \(r.creepScore) · \(FlowText.compactNumber(r.gold))G").font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            GradeBadge(grade: r.grade, size: 26)
            // MVP 欄は常に幅を確保して列を揃える
            MVPBadge(compact: true)
                .opacity(r.isMVP ? 1 : 0)
                .accessibilityHidden(!r.isMVP)
            VStack(alignment: .trailing, spacing: 1) {
                Text(FlowText.duration(r.duration)).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
                Text(FlowText.date(r.date)).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .frame(width: 100, alignment: .trailing)
            Image(systemName: hasReplay ? "play.rectangle.fill" : "chevron.right")
                .font(.system(size: hasReplay ? 15 : 11, weight: .bold))
                .foregroundStyle(hasReplay ? Theme.cyan : Theme.textSecondary)
                .frame(width: 20)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 58)
        .background(
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: 3)
                Spacer()
            }
        )
        .glass(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RecordDetailSheet: View {
    let record: MatchRecord
    let replay: ReplayMeta?
    let onWatch: (BattleLaunch) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// リプレイの読み込み中（メインスレッドの外で復号する。二重に開始しない）。
    @State private var loadingReplay = false
    /// 読み込み（シートを閉じたら取り消す。閉じた後に読み終わっても再生を始めない）。
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            CelestialBackdrop()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(record.won == true ? L("勝利", "Victory") : (record.won == false ? L("敗北", "Defeat") : L("試合終了", "Match Ended")))
                        .font(Theme.title(22))
                        .foregroundStyle(record.won == true ? Theme.gold : (record.won == false ? Theme.danger : Theme.textPrimary))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(FlowText.mode(record.mode)) · \(FlowText.difficulty(record.difficulty)) · \(FlowText.duration(record.duration))")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                        Text(FlowText.date(record.date)).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let replay {
                        let unplayable = ReplayLibrary.compatibility(replay) == .incompatible
                        Button(action: watch) {
                            if loadingReplay {
                                ProgressView().tint(.black).frame(minWidth: 120)
                            } else {
                                Label(unplayable ? L("再生できません", "Can't Play") : L("リプレイを見る", "Watch Replay"),
                                      systemImage: unplayable ? "nosign" : "play.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                        .disabled(loadingReplay || unplayable)
                        .opacity(unplayable ? 0.5 : 1)
                        .accessibilityIdentifier("records_watch_replay")
                    }
                    FlowCloseButton(identifier: "records_detail_close") { dismiss() }
                }
                ScrollView {
                    if let summary = record.summary {
                        MatchScoreTable(summary: summary)
                            .padding(.bottom, 10)
                    } else {
                        playerOnly
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            // シートではルートのトーストが隠れるため、ここにも重ねる
            ToastOverlay()
        }
        .preferredColorScheme(.dark)
        .onDisappear { loadTask?.cancel() }
    }

    private var playerOnly: some View {
        let r = record
        return HStack(spacing: 12) {
            HeroPortraitView(heroID: r.heroID, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.master.hero(r.heroID).map { MasterText.hero($0) } ?? r.heroID)
                    .font(Theme.heading(16)).foregroundStyle(Theme.textPrimary)
                Text("K/D/A \(FlowText.kda(r.kills, r.deaths, r.assists)) · CS \(r.creepScore) · \(FlowText.compactNumber(r.gold)) G · \(L("ダメージ", "Damage")) \(FlowText.compactNumber(r.damageToHeroes))")
                    .font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            GradeBadge(grade: r.grade, size: 34)
            if r.isMVP { MVPBadge() }
        }
        .padding(14)
        .glass(cornerRadius: 14)
    }

    /// リプレイ一覧と同じ起動（ReplayLibrary.loadLaunch: 版数・形式の確認、持ち主の座席、メインスレッドの外での復号）。
    private func watch() {
        guard let meta = replay, !loadingReplay else { return }
        loadingReplay = true
        loadTask = Task { @MainActor in
            let result = await ReplayLibrary.loadLaunch(for: meta, persistence: app.persistence,
                                                        options: ReplayLibrary.playbackOptions(profile: app.profile))
            loadingReplay = false
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let launch):
                FlowFX.confirm(app)
                onWatch(launch)
            case .failure(.missing):
                FlowFX.error(app)
                app.showToast(L("リプレイを読み込めませんでした", "Couldn't load the replay"))
            case .failure(.incompatible):
                FlowFX.error(app)
                app.showToast(L("別のバージョンで記録されたリプレイは再生できません", "This replay was recorded with another version and can't be played"))
            }
        }
    }
}

// MARK: - UI017 実績

struct AchievementsView: View {
    private enum Filter: Hashable { case all, unlocked, inProgress }

    @Environment(AppModel.self) private var app
    @State private var filter: Filter = .all

    private func progress(_ def: AchievementDef) -> AchievementProgress {
        app.profile.achievements[def.id] ?? AchievementProgress()
    }

    private func isUnlocked(_ def: AchievementDef) -> Bool {
        let p = progress(def)
        return p.unlockedAt != nil || p.progress >= def.target
    }

    var body: some View {
        ScreenScaffold(title: L("実績", "Achievements")) {
            let defs = LiveOpsService.achievements
            if defs.isEmpty {
                EmptyStateView(symbol: "trophy", title: L("実績はまだありません", "No achievements yet"),
                               message: L("対戦や育成で条件を満たすと実績が解除されます。", "Play matches to unlock achievements."))
            } else {
                let unlocked = defs.filter { isUnlocked($0) }.count
                let list = defs.filter { d in
                    switch filter {
                    case .all: return true
                    case .unlocked: return isUnlocked(d)
                    case .inProgress: return !isUnlocked(d)
                    }
                }
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                            Text("\(unlocked) / \(defs.count)").font(Theme.mono(15)).foregroundStyle(Theme.textPrimary)
                            CelestialProgressBar(value: Double(unlocked) / Double(max(1, defs.count)), tint: Theme.gold, height: 6)
                                .frame(width: 120)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(L("達成 \(unlocked) / \(defs.count)", "\(unlocked) of \(defs.count) unlocked"))
                        Spacer()
                        CelestialTabs(options: [
                            .init(value: Filter.all, title: L("すべて", "All"), symbol: "square.grid.2x2", identifier: "achv_filter_all"),
                            .init(value: Filter.unlocked, title: L("達成", "Unlocked"), symbol: "checkmark.seal.fill", identifier: "achv_filter_unlocked"),
                            .init(value: Filter.inProgress, title: L("挑戦中", "In progress"), symbol: "hourglass", identifier: "achv_filter_progress"),
                        ], selection: $filter, fills: false)
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(list) { def in
                                achievementCard(def)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func achievementCard(_ def: AchievementDef) -> some View {
        let p = progress(def)
        let unlocked = isUnlocked(def)
        let ratio = def.target > 0 ? min(1, p.progress / def.target) : (unlocked ? 1 : 0)
        return HStack(spacing: 12) {
            Image(systemName: unlocked ? "trophy.fill" : "trophy")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                .frame(width: 46, height: 46)
                .background(HexagonShape().fill(unlocked ? Theme.gold.opacity(0.18) : Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(L(def.titleJa, def.titleEn))
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(L(def.detailJa, def.detailEn))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    CelestialProgressBar(value: ratio, tint: unlocked ? Theme.gold : Theme.cyan, height: 5)
                    Text("\(formatValue(min(p.progress, def.target)))/\(formatValue(def.target))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            VStack(spacing: 4) {
                if def.rewardGems > 0 {
                    RewardChip(attachment: MailAttachment(kind: .gem, amount: def.rewardGems), claimed: p.claimed)
                }
                if p.claimed {
                    // 報酬の無い実績（観戦）は受け取る物が無いので「達成」と出す
                    Label(def.rewardGems > 0 ? L("受取済み", "Claimed") : L("達成", "Achieved"), systemImage: "checkmark")
                        .font(Theme.body(11)).foregroundStyle(Theme.success)
                        .frame(minHeight: 32)
                } else if unlocked {
                    Button(L("受け取る", "Claim")) { claim(def) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("achv_claim_\(def.id)")
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.textSecondary).frame(minHeight: 32)
                }
            }
            .frame(width: 126)
        }
        .padding(10)
        .glass(cornerRadius: 14, tint: unlocked ? Theme.gold : Theme.panelStroke, highlighted: unlocked && !p.claimed)
        .accessibilityElement(children: .contain)
    }

    private func formatValue(_ v: Double) -> String {
        v >= 10_000 ? FlowText.compactNumber(v) : (v.rounded() == v ? "\(Int(v))" : String(format: "%.1f", v))
    }

    private func claim(_ def: AchievementDef) {
        var p = app.profile
        if let gems = LiveOpsService.claimAchievement(id: def.id, profile: &p, now: Date()) {
            app.profile = p
            FlowFX.reward(app)
            app.showToast(L("\(gems) ジェムを受け取りました", "Received \(gems) Gems"))
        } else {
            FlowFX.error(app)
            app.showToast(L("まだ受け取れません", "Not available yet"))
        }
    }
}
