import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI018 リーダーボード（ランキング・AI ラダー）/ UI019 ランク概要 / UI020 ランク報酬。

// MARK: - UI018 リーダーボード（MLBB: 左のメニュー・上の範囲のタブ（世界／サーバー／フレンド）・「シーズン残り時間」・1〜3 位の月桂冠・
// 下に自分の行。Velstria のサーバーは国。左のメニューは中身のある物だけ: ランキングと、架空の AI 50 人の AI ラダー）

struct RankingView: View {
    @Environment(\.isWorldShellEmbedded) private var isEmbedded
    @Environment(AppModel.self) private var app
    @State private var menu: Menu = .ranking
    @State private var scope: Scope = .global
    @State private var card: PublicProfile?

    enum Menu: Hashable { case ranking, aiLadder }
    enum Scope: Hashable, CaseIterable { case global, country, friends }

    var body: some View {
        ScreenScaffold(title: L("リーダーボード", "Leaderboard")) {
            HStack(alignment: .top, spacing: 12) {
                leftMenu.frame(width: isEmbedded ? 102 : 136)
                Group {
                    switch menu {
                    case .ranking: rankingPane
                    case .aiLadder: aiLadderPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .worldPanel(item: $card) { p in
            PublicNameCardView(profile: p).environment(app)
        }
    }

    // MARK: 左のメニュー

    private var leftMenu: some View {
        VStack(spacing: 6) {
            menuButton(.ranking, L("ランキング", "Ranking"), "trophy.fill", id: "ranking_menu_ranking")
            menuButton(.aiLadder, L("AI ラダー", "AI Ladder"), "cpu", id: "ranking_menu_ai")
            Spacer(minLength: 0)
            Button {
                FlowFX.tap(app)
                app.router.push(.rankOverview)
            } label: {
                Label(L("ランク概要", "Rank"), systemImage: "crown.fill")
                    .font(Celestial.heading(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("ranking_overview")
        }
    }

    private func menuButton(_ m: Menu, _ title: String, _ symbol: String, id: String) -> some View {
        let selected = menu == m
        return Button {
            guard menu != m else { return }
            app.audio.play(.uiTab)
            withAnimation(.easeInOut(duration: 0.2)) { menu = m }
        } label: {
            Label(title, systemImage: symbol)
                .font(Celestial.heading(13))
                .foregroundStyle(selected ? Color(red: 0.16, green: 0.10, blue: 0.03) : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 10)
                .background(HomeChamfer(cut: 7).fill(selected ? AnyShapeStyle(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                                                              : AnyShapeStyle(Celestial.ink.opacity(0.8))))
                .overlay(HomeChamfer(cut: 7).stroke(selected ? HomeStyle.goldLight : Celestial.ice.opacity(0.4), lineWidth: selected ? 1 : 0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: ランキング（relay の集計）

    private var countryCode: String? { app.profile.countryCode.flatMap(CountryFlag.normalized) }

    private func rankingScope(_ s: Scope) -> RankingScope? {
        switch s {
        case .global: return .global
        case .country: return countryCode.map { .country($0) }
        case .friends: return .friends
        }
    }

    private var rankingPane: some View {
        let days = SeasonService.daysLeft(at: Date())
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                CelestialTabs(options: [
                    CelestialTab(value: Scope.global, title: L("世界", "World"), symbol: nil, identifier: "ranking_scope_global"),
                    CelestialTab(value: Scope.country, title: L("国・地域", "Country"), symbol: nil, identifier: "ranking_scope_country"),
                    CelestialTab(value: Scope.friends, title: L("フレンド", "Friends"), symbol: nil, identifier: "ranking_scope_friends"),
                ], selection: $scope, fills: false, onChange: { _ in app.audio.play(.uiTab) })
                Spacer(minLength: 4)
                Text(L("シーズン残り時間：\(days)日", "Season ends in \(days)d"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            rankingContent
        }
        .task(id: scope) {
            if let s = rankingScope(scope) { await app.ranking.load(s) }
        }
    }

    @ViewBuilder private var rankingContent: some View {
        if !app.syncsCloudRank {
            EmptyStateView(symbol: "globe", title: L("オンライン機能に同意すると見られます", "Agree to the online rules to see the ranking"),
                           message: L("ランキングには、オンラインに同意したプレイヤーの今シーズンの最高ランクが並びます。架空の AI との順位は「AI ラダー」で見られます。",
                                      "The ranking lists the best rank this season of players who agreed to the online rules. See the AI Ladder for your place among AI rivals."))
                .glass(cornerRadius: 14)
        } else if let s = rankingScope(scope) {
            let page = app.ranking.pages[s]
            VStack(spacing: 6) {
                if let page, !page.entries.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(page.entries) { e in
                                rankingRow(e.position, e.profile, isMe: e.profile.code == app.profile.friendCode)
                            }
                        }
                    }
                } else if app.ranking.loading.contains(s) {
                    ProgressView().tint(Celestial.ice).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView(symbol: "trophy", title: app.ranking.lastError ?? L("まだ誰もいません", "No one here yet"),
                                   message: L("ランク戦をして名刺を公開すると、ここに並びます。", "Play ranked to appear here."))
                }
                myRow(page)
            }
        } else {
            EmptyStateView(symbol: "flag.slash", title: L("国・地域が設定されていません", "No country set"),
                           message: L("プロフィールで国・地域を選ぶと、同じ国のランキングが見られます。", "Choose your country in your profile to see its ranking."))
        }
    }

    /// いちばん下に固定する自分の行（範囲の外なら「ランク外」）。
    private func myRow(_ page: RankingPage?) -> some View {
        let r = app.profile.rank
        let mine = PublicRank(tier: r.tier.rawValue, division: r.division, stars: r.stars)
        return HStack(spacing: 10) {
            Text(page?.me.map { "\($0.position)" } ?? L("ランク外", "Unranked"))
                .font(Theme.heading(13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64)
            HeroPortraitView(heroID: app.profile.avatarHeroID, size: 34, showsRole: false)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .topLeading) { CountryFlagBadge(code: countryCode, size: 12).offset(x: -3, y: -3) }
            Text(app.onlineName).font(Celestial.heading(13)).foregroundStyle(HomeStyle.goldLight).lineLimit(1)
            Spacer(minLength: 4)
            rankLabel(page?.me?.profile.seasonBest ?? mine)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 46)
        .background(HomeChamfer(cut: 8).fill(Color(red: 0.20, green: 0.40, blue: 0.70).opacity(0.45)))
        .overlay(HomeChamfer(cut: 8).stroke(HomeStyle.goldLight.opacity(0.6), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ranking_my_row")
    }

    private func rankingRow(_ position: Int, _ p: PublicProfile, isMe: Bool) -> some View {
        Button {
            FlowFX.tap(app)
            card = p
        } label: {
            HStack(spacing: 10) {
                positionBadge(position)
                    .frame(width: 64)
                HeroPortraitView(heroID: p.avatar ?? HeroRoster.defaultHeroID, size: 36, showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(alignment: .topLeading) { CountryFlagBadge(code: p.country, size: 12).offset(x: -3, y: -3) }
                Text(PlayerNameRules.shown(p.name))
                    .font(Celestial.heading(13))
                    .foregroundStyle(isMe ? HomeStyle.goldLight : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                rankLabel(p.seasonBest)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .background(HomeChamfer(cut: 8).fill(position <= 3 ? AnyShapeStyle(LinearGradient(colors: [laurelColor(position).opacity(0.25), Celestial.ink.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                                               : AnyShapeStyle(Celestial.ink.opacity(0.7))))
            .overlay(HomeChamfer(cut: 8).stroke(position <= 3 ? laurelColor(position).opacity(0.6) : Celestial.ice.opacity(0.25), lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ranking_row_\(position)")
    }

    /// 順位（1〜3 位は金・銀・銅の月桂冠）。
    @ViewBuilder private func positionBadge(_ position: Int) -> some View {
        if position <= 3 {
            HStack(spacing: 0) {
                Image(systemName: "laurel.leading")
                Text("\(position)").font(.system(size: 17, weight: .black, design: .serif))
                Image(systemName: "laurel.trailing")
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(laurelColor(position))
        } else {
            Text("\(position)").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
        }
    }

    private func laurelColor(_ position: Int) -> Color {
        switch position {
        case 1: return Theme.gold
        case 2: return Color(white: 0.82)
        default: return Color(red: 0.80, green: 0.52, blue: 0.32)
        }
    }

    /// 段位章・段位名・星（ミシックは紫の星と累計。MLBB の「Iミシック ★1886」）。
    private func rankLabel(_ r: PublicRank) -> some View {
        let tier = PublicRankText.tier(r)
        return HStack(spacing: 4) {
            RankCrest(tier: tier, size: 22)
            Text(PublicRankText.name(r)).font(Celestial.heading(12)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Image(systemName: "star.fill").font(.system(size: 11))
                .foregroundStyle(tier == .mythic ? Color(red: 0.86, green: 0.55, blue: 1) : Theme.gold)
            Text("\(r.stars)").font(Theme.mono(12)).foregroundStyle(HomeStyle.goldLight).monospacedDigit()
        }
    }

    // MARK: AI ラダー（端末の中の架空の 50 人）

    private var aiLadderPane: some View {
        let ladder = RankService.ladder(for: app.profile)
        return HStack(alignment: .top, spacing: 12) {
            sidePanel(ladder)
                .frame(width: 210)
            if ladder.isEmpty {
                EmptyStateView(symbol: "list.number", title: L("ランキングを準備中です", "The ladder is being prepared"),
                               message: L("ランク戦をプレイすると、AI ライバルとの順位が表示されます。", "Play ranked matches to see where you stand against AI rivals."))
                    .glass(cornerRadius: 16)
            } else {
                ladderList(ladder)
            }
        }
    }

    private func sidePanel(_ ladder: [LadderEntry]) -> some View {
        let p = app.profile
        let position = ladder.firstIndex { $0.isPlayer }.map { $0 + 1 }
        return VStack(alignment: .leading, spacing: 10) {
            Label(L("オフラインの対AIラダー", "Offline ladder vs AI"), systemImage: "cpu")
                .font(Theme.heading(13))
                .foregroundStyle(Theme.cyan)
            Text(L("この順位は端末内のみで計算されます。ライバルは AI が操作する架空のプレイヤーで、ランク戦の結果に応じて順位が変動します。",
                   "This ladder is computed on your device. Rivals are fictional AI-controlled players; your position changes with your ranked results."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.panelStroke)
            HStack(spacing: 10) {
                RankEmblemView(tier: p.rank.tier, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RankService.displayName(p.rank)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary)
                    Text(L("レート \(RankService.rating(p.rank))", "Rating \(RankService.rating(p.rank))"))
                        .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                }
            }
            if let position {
                Text(L("現在 \(position) 位 / \(ladder.count) 人", "#\(position) of \(ladder.count)"))
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.gold)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(cornerRadius: 16)
    }

    private func ladderList(_ ladder: [LadderEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(ladder.enumerated()), id: \.element.id) { i, e in
                        ladderRow(position: i + 1, entry: e)
                            .id(e.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                if let me = ladder.first(where: { $0.isPlayer }) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(me.id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func ladderRow(position: Int, entry: LadderEntry) -> some View {
        HStack(spacing: 10) {
            Group {
                if position <= 3 {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(position == 1 ? Theme.gold : (position == 2 ? Color(white: 0.82) : Color(red: 0.8, green: 0.5, blue: 0.3)))
                        .overlay(Text("\(position)").font(.system(size: 9, weight: .black)).foregroundStyle(.black).offset(y: -2))
                } else {
                    Text("\(position)").font(Theme.mono(14)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 36)
            RankEmblemView(tier: entry.tier, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(Theme.heading(14))
                        .foregroundStyle(entry.isPlayer ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                    if entry.isPlayer {
                        Text(L("あなた", "YOU"))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.gold))
                    } else {
                        Image(systemName: "cpu").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel("AI")
                    }
                }
                Text(RankService.tierName(entry.tier)).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(entry.rating)")
                .font(Theme.mono(15))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .glass(cornerRadius: 12, tint: entry.isPlayer ? Theme.gold : Theme.panelStroke, highlighted: entry.isPlayer)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(entry.isPlayer ? "ranking_player_row" : "ranking_ai_row_\(position)")
    }
}

// MARK: - UI019 ランク概要（MLBB 2.2.16 の作り: 左上にシーズン名と残り日数、中央に段位章と星、右上に前シーズンのメダル、
// 右下に勝率・総試合数・最高ランク・保護ポイント、下のタブ（シーズン情報／シーズンの道のり／ミシックへの道））

struct RankOverviewView: View {
    @Environment(\.isWorldShellEmbedded) private var isEmbedded
    @Environment(AppModel.self) private var app
    @State private var panel: Panel?

    enum Panel: String, Identifiable, CaseIterable {
        case season, road, mythic
        var id: String { rawValue }

        var title: String {
            switch self {
            case .season: return L("シーズン情報", "Season Info")
            case .road: return L("シーズンの道のり", "Season Journey")
            case .mythic: return L("ミシックへの道", "Road to Mythic")
            }
        }

        var symbol: String {
            switch self {
            case .season: return "info.circle.fill"
            case .road: return "flag.checkered"
            case .mythic: return "stairs"
            }
        }
    }

    /// シーズンの道のりの試合数（MLBB は 20 試合でシーズンの報酬）。
    static let journeyMatches = 20

    var body: some View {
        ScreenScaffold(title: L("ランク", "Rank")) {
            VStack(spacing: 6) {
                if isEmbedded {
                    ScrollView {
                        VStack(spacing: 12) {
                            HStack {
                                seasonBadge
                                Spacer()
                                previousSeason
                            }
                            VStack(spacing: 12) {
                                crestBlock
                                statsGrid
                            }
                            actions
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .worldShellCard()
                    }
                } else {
                ZStack {
                    crestBlock
                    seasonBadge
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    previousSeason
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    actions
                        .frame(width: 190)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    statsGrid
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .frame(maxHeight: .infinity)
                }
                tabsRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .worldPanel(item: $panel) { p in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch p {
                        case .season: rules
                        case .road: journey
                        case .mythic: tierLadder
                        }
                    }
                    .padding(16)
                }
                .background(Celestial.ink)
                .navigationTitle(p.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("閉じる", "Close")) { panel = nil }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .environment(app)
        }
        .onAppear(perform: refreshSeason)
    }

    // MARK: 中央・四隅

    /// 中央: 段位章・星（ミシックは紫の星と「★14/25」）・段位名の帯・スターポイント。
    private var crestBlock: some View {
        let r = app.profile.rank
        return VStack(spacing: 6) {
            RankCrest(tier: r.tier, size: 112)
                .glowPulse(FlowText.tierColors(r.tier)[0], radius: 16)
            if r.tier == .mythic {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(Color(red: 0.86, green: 0.55, blue: 1))
                    Text(ModeTileLayout.mythicNext(r.stars).map { "\(r.stars)/\($0)" } ?? "\(r.stars)")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
            } else {
                RankStarsView(stars: r.stars, maxStars: RankService.maxStars(r.tier), size: 20)
            }
            Text(RankService.shortName(r) + (r.tier == .mythic ? "" : " " + RankService.roman(r.division)))
                .font(Celestial.title(20))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 30)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.35)))
            if r.tier != .mythic {
                // 文字は棒の上に（横に並べると SE で右下の戦績のカードに隠れる）
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L("スターポイント", "Star Points")).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                        Text("\(r.starPoints)/\(RankService.starPointCap(r.tier))").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                    }
                    CelestialProgressBar(value: RankService.progress(r.starPoints, cap: RankService.starPointCap(r.tier)), tint: Theme.gold, height: 4)
                        .frame(width: 130)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 左上: シーズン名と残り日数（MLBB: 「⌛90d」）。
    private var seasonBadge: some View {
        let now = Date()
        let season = SeasonService.season(at: now)
        let days = SeasonService.daysLeft(at: now)
        return VStack(alignment: .leading, spacing: 2) {
            Text(L("シーズン \(season)", "Season \(season)"))
                .font(Celestial.title(17))
                .foregroundStyle(Theme.textPrimary)
            Label("\(days)d", systemImage: "hourglass")
                .font(Theme.mono(12))
                .foregroundStyle(Celestial.ice)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("シーズン \(season) · 残り \(days) 日", "Season \(season) · \(days) \(days == 1 ? "day" : "days") left"))
        .accessibilityIdentifier("rank_season")
    }

    /// 右上: 前シーズンのメダル（そのシーズンの最高ランクの段位章）。
    @ViewBuilder private var previousSeason: some View {
        if let last = app.profile.rank.endedSeasons.last {
            VStack(spacing: 2) {
                RankCrest(tier: last.highestTier, size: 40)
                Text(L("S\(last.season) 最高", "S\(last.season) best"))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("rank_previous_season")
        }
    }

    /// 右下: 勝率・総試合数・最高ランク・保護ポイント（今シーズン）。
    private var statsGrid: some View {
        let r = app.profile.rank
        let games = r.seasonWins + r.seasonLosses
        let highest = r.highestTier == .mythic ? RankService.mythicName(stars: r.highestMythicStars) : RankService.tierName(r.highestTier)
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                FlowStatCell(title: L("勝率", "Win%"), value: games > 0 ? "\(r.seasonWins * 100 / games)%" : "—")
                FlowStatCell(title: L("総試合数", "Matches"), value: "\(games)")
            }
            HStack(spacing: 6) {
                FlowStatCell(title: L("最高ランク", "Highest"), value: highest)
                FlowStatCell(title: L("保護ポイント", "Protection"), value: "\(r.protectionPoints)/\(RankService.protectionCap(r.tier))")
            }
        }
        .frame(width: 230)
    }

    /// 下のタブ（押すとその中身を開く）。
    private var tabsRow: some View {
        HStack(spacing: 8) {
            ForEach(Panel.allCases) { p in
                Button {
                    FlowFX.tap(app)
                    panel = p
                } label: {
                    Label(p.title, systemImage: p.symbol)
                        .font(Celestial.heading(13))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(HomeChamfer(cut: 7).fill(Celestial.ink.opacity(0.8)))
                        .overlay(HomeChamfer(cut: 7).stroke(Celestial.ice.opacity(0.45), lineWidth: 0.6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rank_tab_\(p.rawValue)")
            }
        }
    }

    /// シーズンの道のり: 今シーズンのランク戦の数（20 試合まで）と、シーズン報酬（前のシーズンの最高ランクのコイン）。
    private var journey: some View {
        let r = app.profile.rank
        let games = r.seasonWins + r.seasonLosses
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: L("今シーズンのランク戦", "Ranked matches this season"), symbol: "flag.checkered",
                         trailing: "\(min(games, Self.journeyMatches))/\(Self.journeyMatches)")
            CelestialProgressBar(value: Double(min(games, Self.journeyMatches)) / Double(Self.journeyMatches), tint: Theme.gold, height: 8)
            SectionTitle(title: L("シーズン報酬（今シーズンの最高ランク）", "Season rewards (highest rank this season)"), symbol: "gift.fill")
            ForEach(RankTier.allCases.reversed()) { t in
                HStack(spacing: 10) {
                    RankCrest(tier: t, size: 28)
                    Text(RankService.tierName(t)).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    ForEach(Array(SeasonService.rewards(for: t).enumerated()), id: \.offset) { _, a in
                        RewardChip(attachment: a)
                    }
                }
            }
        }
    }

    /// 開いた時: 起動したまま新しいシーズンになっていれば下げ、前のシーズンの報酬をメールで送る（SeasonService）。
    private func refreshSeason() {
        var p = app.profile
        let sent = SeasonService.refresh(profile: &p, now: Date())
        guard p != app.profile else { return }
        app.profile = p
        if let last = sent.last {
            app.showToast(L("シーズン \(last.season) の報酬がメールに届きました", "Season \(last.season) rewards arrived in your mail"))
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                FlowFX.confirm(app)
                MatchFlowIntent.present(.ranked, app: app)
            } label: {
                Label(L("ランク戦を開始", "Play Ranked"), systemImage: "crown.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .glowPulse(Theme.gold, radius: 10)
            .accessibilityIdentifier("rank_play")
            // ランキングの入口はロビーのトロフィーだけ（入口を 1 つに）
            HStack(spacing: 8) {
                Button {
                    FlowFX.tap(app)
                    app.router.push(.rankRewards)
                } label: {
                    Label(L("ランク報酬", "Rewards"), systemImage: "gift.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .overlay(alignment: .topTrailing) { FlowCountBadge(count: HomeBadges.claimableRankRewards(app.profile)) }
                .accessibilityIdentifier("rank_rewards")
            }
        }
        // 「ランク戦を開始」の発光がスクロール領域の上端で切れないよう余白を取る
        .padding(.top, 10)
    }

    private var tierLadder: some View {
        let r = app.profile.rank
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: L("ランク一覧", "Tiers"), symbol: "stairs")
            ForEach(RankTier.allCases.reversed()) { t in
                let current = t == r.tier
                let reached = t <= r.highestTier
                let diff = RankService.botDifficulty(for: RankState(tier: t))
                HStack(spacing: 10) {
                    RankEmblemView(tier: t, size: current ? 38 : 30)
                        .opacity(reached ? 1 : 0.45)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(RankService.tierName(t))
                            .font(Theme.heading(current ? 15 : 13))
                            .foregroundStyle(current ? Theme.gold : Theme.textPrimary)
                        Text(t == .mythic ? L("星の累計（Hミシック 25・Gミシック 50・Iミシック 100）", "Cumulative stars (Honor 25 · Glory 50 · Immortal 100)")
                             : L("\(RankService.divisions(t)) 段階 × 星 \(RankService.maxStars(t))", "\(RankService.divisions(t)) divisions × \(RankService.maxStars(t)) stars"))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(L("敵AI \(FlowText.difficulty(diff.enemy))", "Enemy AI \(FlowText.difficulty(diff.enemy))"))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                    if current {
                        Text(L("現在", "Current"))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.gold))
                    } else if reached {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                            .accessibilityLabel(L("到達済み", "Reached"))
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 46)
                .glass(cornerRadius: 12, tint: current ? Theme.gold : Theme.panelStroke, highlighted: current)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: L("ルール", "Rules"), symbol: "info.circle.fill")
            // RankService の規則（MLBB と同じ）。段位の数と星の数はティアごとに違うので上のランク一覧に出す
            ruleRow("arrow.up.circle.fill", Theme.success, L("勝利で星 +1。星が満タンの状態で勝つと次の段位へ昇格します（I からは上のティアへ）。ミシックでは星を累計します。",
                                                            "Win: +1 star. Winning with full stars promotes you to the next division (from I, to the next tier). In Mythic, stars add up."))
            ruleRow("arrow.down.circle.fill", Theme.danger, L("敗北で星 −1。星 0 で負けると 1 つ下の段位へ下がります。ウォリアーでは星が減らず、ティアの最下段から下のティアへは落ちません（ミシックの星 0 からはレジェンド I へ）。",
                                                              "Loss: −1 star; at 0 stars you drop a division. Warrior never loses stars, and you can't drop below a tier's lowest division (except Mythic at 0 stars, to Legend I)."))
            ruleRow("star.circle.fill", Theme.gold, pointsRule)
            ruleRow("calendar", Theme.cyan, seasonRule)
            ruleRow("cpu", Theme.cyan, L("ランクが上がるほど AI が強くなります。", "Higher ranks face stronger AI."))
            ruleRow("hand.raised.fill", Theme.gold, L("ランク戦ではドラフトで交互にピックします（同じヒーローは 1 人だけ）。", "In ranked, teams take turns picking (each hero once per match)."))
        }
        .padding(12)
        .glass(cornerRadius: 14)
    }

    /// ポイントの満タン（ティアごと。RankService.starPointCap / protectionCap から作る）。
    private var pointsRule: String {
        let caps = RankTier.allCases.filter { $0 != .mythic }
            .map { "\(RankService.tierName($0)) \(RankService.starPointCap($0))" }
            .joined(separator: L("・", ", "))
        let mythic = RankService.protectionCap(.mythic)
        return L("スターポイントは勝利でたまり、満タン（\(caps)）で星 +1。ミシックにはありません。保護ポイントは敗北でたまり、満タン（同じ値。ミシック \(mythic)）になると次の敗北で星が減りません。",
                 "Star Points build up from wins; when full (\(caps)) you gain a star. Mythic has none. Protection Points build up from losses; when full (same values, Mythic \(mythic)) your next loss costs no star.")
    }

    /// シーズン（SeasonService: 13 週。新しいシーズンの下げ方の例と、前のシーズンの報酬）。
    private var seasonRule: String {
        let weeks = Int(SeasonService.seasonLength / (7 * 86_400))
        let low = SeasonService.rewards(for: .warrior).first?.amount ?? 0
        let high = SeasonService.rewards(for: .mythic).first?.amount ?? 0
        return L("シーズンは \(weeks) 週（約 3 か月）。新しいシーズンの最初にランクが下がります（例: ミシック〜Gミシック → エピック II、Iミシック → エピック I・星 1）。前のシーズンの最高ランクに応じて \(low)〜\(high) コインがメールで届きます。",
                 "A season lasts \(weeks) weeks (about 3 months). When a new season starts, your rank drops (e.g. Mythic to Mythical Glory → Epic II, Mythical Immortal → Epic I with 1 star). Rewards of \(low)–\(high) coins for your highest rank last season arrive by mail.")
    }

    private func ruleRow(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        Label {
            Text(text).font(Theme.body(12)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

// MARK: - UI020 ランク報酬

struct RankRewardsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("ランク報酬", "Rank Rewards")) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.cyan)
                    Text(L("到達したランクの報酬を 1 回ずつ受け取れます。シーズン報酬は、シーズンの終わりに最高ランクに応じてメールで届きます。",
                           "Claim a one-time reward for each tier you reach. Season rewards for your highest tier arrive by mail when the season ends."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    RankInlineView(rank: app.profile.rank, emblemSize: 22)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(RankTier.allCases) { t in
                            rewardRow(t)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func rewardRow(_ t: RankTier) -> some View {
        let rank = app.profile.rank
        let rewards = RankService.tierRewards(t)
        let reached = t <= rank.highestTier
        let claimed = rank.claimedTierRewards.contains(t.rawValue)
        return HStack(spacing: 12) {
            RankEmblemView(tier: t, size: 42)
                .opacity(reached ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 5) {
                Text(RankService.tierName(t))
                    .font(Theme.heading(15))
                    .foregroundStyle(reached ? Theme.textPrimary : Theme.textSecondary)
                if rewards.isEmpty {
                    Text(L("このランクの報酬はありません", "No reward for this tier"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    FlowWrapLayout(spacing: 6) {
                        ForEach(rewards.indices, id: \.self) { i in
                            RewardChip(attachment: rewards[i], claimed: claimed)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Group {
                if claimed {
                    Label(L("受取済み", "Claimed"), systemImage: "checkmark.circle.fill")
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.success)
                } else if reached && !rewards.isEmpty {
                    Button(L("受け取る", "Claim")) { claim(t) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("rank_claim_\(t.rawValue)")
                } else if !reached {
                    Label(L("未到達", "Locked"), systemImage: "lock.fill")
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .glass(cornerRadius: 14, tint: reached && !claimed && !rewards.isEmpty ? Theme.gold : Theme.panelStroke,
               highlighted: reached && !claimed && !rewards.isEmpty)
        .accessibilityElement(children: .contain)
    }

    private func claim(_ t: RankTier) {
        var p = app.profile
        let rewards = RankService.tierRewards(t)
        if RankService.claimTierReward(t, profile: &p) {
            app.profile = p
            FlowFX.reward(app)
            app.showToast(L("受け取りました: ", "Received: ") + FlowText.attachmentsSummary(rewards, master: app.master))
        } else {
            FlowFX.error(app)
            app.showToast(L("受け取れませんでした", "Couldn't claim the reward"))
        }
    }
}
