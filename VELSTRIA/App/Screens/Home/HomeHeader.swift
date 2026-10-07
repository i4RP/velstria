import SwiftUI
import VelstriaCore

// 担当: home-chrome。ホームのヘッダー: プレイヤープレート・ランク・タイトルロゴ・通貨・アイコン列（メール / お知らせ / 設定 / メニュー）。
// 幅に収まる構成を ViewThatFits で選ぶ（広い端末はロゴとランク名まで、狭い端末は省く）。

struct HomeHeader: View {
    let metrics: HomeMetrics
    let now: Date
    let animated: Bool
    let onMenu: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = metrics
        let rect = CGRect(x: m.contentMinX, y: m.safeArea.top, width: m.contentMaxX - m.contentMinX,
                          height: m.headerRect.height - m.safeArea.top)
        ViewThatFits(in: .horizontal) {
            row(logo: true, rankName: true, compactCurrency: false)
            row(logo: true, rankName: false, compactCurrency: false)
            row(logo: false, rankName: true, compactCurrency: false)
            row(logo: false, rankName: false, compactCurrency: false)
            row(logo: false, rankName: false, compactCurrency: true)
        }
        .homePlaced(in: rect)
    }

    private func row(logo: Bool, rankName: Bool, compactCurrency: Bool) -> some View {
        HStack(spacing: 6) {
            HomePlayerPlate()
            HomeRankChip(showsName: rankName)
            Spacer(minLength: 6)
            if logo {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: metrics.logoHeight)
                    .shadow(color: Theme.cyan.opacity(0.45), radius: 8)
                    .accessibilityLabel("VELSIA")
                Spacer(minLength: 6)
            }
            HomeCurrencyPlate(compact: compactCurrency)
            HStack(spacing: 0) {
                HomeIconButton(symbol: "envelope.fill", label: L("メール", "Mail"),
                               badge: HomeBadges.unreadMail(app.profile, now: now), identifier: "home_mail") {
                    FlowFX.tap(app)
                    app.router.push(.mail)
                }
                HomeIconButton(symbol: "megaphone.fill", label: L("お知らせ", "News"),
                               badge: HomeBadges.unreadNotices(app.profile), identifier: "home_notices") {
                    FlowFX.tap(app)
                    app.router.push(.notices)
                }
                HomeIconButton(symbol: "gearshape.fill", label: L("設定", "Settings"), identifier: "home_settings") {
                    FlowFX.tap(app)
                    app.router.push(.settings)
                }
                HomeIconButton(symbol: "line.3.horizontal", label: L("メニュー", "Menu"),
                               badge: HomeMenuItem.totalBadge(profile: app.profile), tint: Theme.gold, identifier: "home_menu") {
                    FlowFX.tap(app)
                    onMenu()
                }
            }
        }
    }
}

// MARK: - プレイヤープレート

/// アバター（六角形・金の縁）+ 名前 + レベルと経験値。押すとプロフィールへ。
private struct HomePlayerPlate: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.profile
        let name = p.displayName.isEmpty ? L("プレイヤー", "Player") : p.displayName
        let required = FlowAccountXP.required(forLevel: p.accountLevel)
        Button {
            FlowFX.tap(app)
            app.router.push(.profile)
        } label: {
            HStack(spacing: 8) {
                HomeAvatar(heroID: p.avatarHeroID, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(HomeFont.tech(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: 92, alignment: .leading)
                    HStack(spacing: 5) {
                        Text("Lv \(p.accountLevel)")
                            .font(HomeFont.tech(11))
                            .foregroundStyle(Theme.gold)
                            .fixedSize()
                        HomeBar(value: Double(p.accountXP) / Double(max(1, required)), tint: Theme.cyan)
                            .frame(width: 50, height: 4)
                    }
                }
            }
            .padding(.leading, 3)
            .padding(.trailing, 10)
            .frame(height: 44)
            .homePanel(cut: 10, corners: [.bottomTrailing], tint: Theme.cyan, opacity: 0.55, accent: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("プロフィール、\(name)、レベル \(p.accountLevel)", "Profile, \(name), level \(p.accountLevel)"))
        .accessibilityIdentifier("home_profile")
    }
}

/// 六角形に切り抜いたアバター。
struct HomeAvatar: View {
    let heroID: String
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let art = PortraitArt.hero(heroID) {
                Image(uiImage: art).resizable().interpolation(.high).scaledToFill()
            } else {
                LinearGradient(colors: [Color(hue: Theme.heroHue(heroID), saturation: 0.6, brightness: 0.8), HomeStyle.ink],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: size, height: size)
        .clipShape(HexagonShape())
        .overlay(HexagonShape().stroke(HomeStyle.goldGradient, lineWidth: 1.6))
        .shadow(color: Theme.gold.opacity(0.5), radius: 4)
        .accessibilityHidden(true)
    }
}

/// 細い進捗バー（光る先端つき）。
struct HomeBar: View {
    var value: Double
    var tint: Color = Theme.cyan

    var body: some View {
        GeometryReader { geo in
            let v = min(1, max(0, value.isFinite ? value : 0))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.height, geo.size.width * v))
                    .shadow(color: tint.opacity(0.8), radius: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - ランク

private struct HomeRankChip: View {
    let showsName: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let rank = app.profile.rank
        let tierColor = FlowText.tierColors(rank.tier)[0]
        Button {
            FlowFX.tap(app)
            app.router.push(.rankOverview)
        } label: {
            HStack(spacing: 6) {
                RankEmblemView(tier: rank.tier, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    if showsName {
                        Text(RankService.displayName(rank))
                            .font(HomeFont.tech(11.5))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if rank.tier == .starRingSovereign {
                        Text("\(rank.points) pt").font(HomeFont.tech(10)).foregroundStyle(Theme.gold)
                    } else {
                        RankStarsView(stars: rank.stars, size: 9)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .homePanel(cut: 8, corners: .antiDiagonal, tint: tierColor, opacity: 0.55, accent: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.95))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ランク: ", "Rank: ") + RankService.displayName(rank))
        .accessibilityIdentifier("home_rank")
    }
}

// MARK: - 通貨

/// コイン | ジェム を仕切りで連結したプレート + 「＋」。押すと通貨ストアへ。
private struct HomeCurrencyPlate: View {
    let compact: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let coin = app.profile.starlightCoin
        let gem = app.profile.totalGem
        Button {
            FlowFX.tap(app)
            app.router.push(.currencyStore)
        } label: {
            HStack(spacing: 0) {
                cell(symbol: "star.circle.fill", tint: Theme.gold, amount: coin)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.cyan.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 1, height: 22)
                cell(symbol: "diamond.fill", tint: Theme.cyan, amount: gem)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(HomeStyle.onGold)
                    .frame(width: 20, height: 20)
                    .background(HomeDiamond().fill(HomeStyle.goldGradient).frame(width: 24, height: 24))
                    .padding(.horizontal, 8)
            }
            .frame(height: 32)
            .homePanel(cut: 7, corners: .all, tint: Theme.gold, opacity: 0.6, accent: false)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("通貨ストア、コイン \(coin)、ジェム \(gem)", "Currency store, \(coin) coins, \(gem) gems"))
        .accessibilityIdentifier("home_currency")
    }

    private func cell(symbol: String, tint: Color, amount: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.8), radius: 3)
            HomeTabularNumber(text: HomeFormat.currency(amount, compact: compact), size: 13)
        }
        .padding(.horizontal, 8)
    }
}
