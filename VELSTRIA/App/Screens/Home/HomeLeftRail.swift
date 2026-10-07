import SwiftUI
import VelstriaCore

// 担当: home-chrome。ホームの左レール: イベントバナー・スターパスバナー（大）+ ミッション / ショップ / 戦績（リスト）。

struct HomeLeftRail: View {
    let metrics: HomeMetrics
    let now: Date
    let animated: Bool

    var body: some View {
        let m = metrics
        VStack(spacing: m.spacing) {
            HomeEventBanner(now: now, animated: animated)
                .frame(height: m.bannerHeight)
            HomePassBanner(animated: animated)
                .frame(height: m.bannerHeight)
            ForEach(HomeQuickLink.allCases) { link in
                HomeQuickLinkRow(link: link, compact: m.isCompact)
                    .frame(height: m.listItemHeight)
            }
            Spacer(minLength: 0)
        }
        .homePlaced(in: m.leftRailRect)
    }
}

// MARK: - バナー

/// 開催中イベント（無ければ開催予定の案内）。キーアートを背景にした「EVENT」バナー。
private struct HomeEventBanner: View {
    let now: Date
    let animated: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let event = LiveOpsService.activeEvents(now: now).first
        let title = event?.title ?? L("イベント", "Events")
        let detail = event.map { HomeFormat.remaining($0.end.timeIntervalSince(now)) } ?? L("開催予定を確認", "See upcoming")
        let shape = HomeChamfer(cut: 12)
        Button {
            FlowFX.tap(app)
            app.router.push(.events)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // 絵の大きさでバナーが押し広げられないよう、領域いっぱいの透明な面に重ねて切り抜く
                Color.clear
                    .overlay {
                        Image("LoadingKeyArt")
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                LinearGradient(colors: [HomeStyle.ink.opacity(0.1), HomeStyle.ink.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                if animated { HomeSheen(period: 5, tint: .white.opacity(0.7)) }
                VStack(alignment: .leading, spacing: 1) {
                    HomeTag(text: "EVENT", tint: HomeStyle.ember)
                    Spacer(minLength: 0)
                    Text(title)
                        .font(HomeFont.tech(13.5))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black, radius: 2)
                    Label(detail, systemImage: "clock.fill")
                        .font(HomeFont.label(10))
                        .foregroundStyle(HomeStyle.goldLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .clipShape(shape)
            .homePanel(cut: 12, tint: HomeStyle.ember, opacity: 0, highlighted: true)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle(scale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("イベント: ", "Event: ") + title + "、" + detail)
        .accessibilityIdentifier("home_events")
    }
}

/// スターパス（レベル・進捗・プレミアム）。金基調。
private struct HomePassBanner: View {
    let animated: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let pass = app.profile.pass
        let level = LiveOpsService.passLevel(xp: pass.xp)
        let progress = level >= LiveOpsService.passMaxLevel
            ? 1 : Double(LiveOpsService.passXPInLevel(xp: pass.xp)) / Double(LiveOpsService.passXPPerLevel)
        let claimable = LiveOpsService.claimablePassRewardCount(profile: app.profile)
        let shape = HomeChamfer(cut: 12)
        Button {
            FlowFX.tap(app)
            app.router.push(.starPass)
        } label: {
            ZStack(alignment: .leading) {
                LinearGradient(colors: [Color(red: 0.32, green: 0.20, blue: 0.05), HomeStyle.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                FourPointStar(innerRatio: 0.2)
                    .fill(LinearGradient(colors: [HomeStyle.goldLight.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 70, height: 70)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .offset(x: 16, y: -8)
                if animated { HomeSheen(period: 6, tint: HomeStyle.goldLight.opacity(0.7)) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        HomeTag(text: "STAR PASS", tint: Theme.gold)
                        if pass.hasPremium {
                            Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(HomeStyle.goldLight)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("Lv").font(HomeFont.tech(10)).foregroundStyle(HomeStyle.goldLight)
                        Text("\(level)").font(HomeFont.italic(19)).foregroundStyle(.white)
                        Text("/ \(LiveOpsService.passMaxLevel)").font(HomeFont.label(10)).foregroundStyle(Theme.textSecondary)
                    }
                    HomeBar(value: progress, tint: Theme.gold).frame(height: 4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .clipShape(shape)
            .homePanel(cut: 12, tint: Theme.gold, opacity: 0, highlighted: claimable > 0)
            .overlay(alignment: .topTrailing) { FlowCountBadge(count: claimable).offset(x: 3, y: -4) }
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle(scale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("スターパス レベル \(level)", "Star Pass level \(level)"))
        .accessibilityIdentifier("home_starPass")
    }
}

/// バナー左上の小さな札。
struct HomeTag: View {
    let text: String
    var tint: Color = Theme.cyan

    var body: some View {
        Text(text)
            .font(HomeFont.italic(9))
            .tracking(1)
            .foregroundStyle(HomeStyle.onGold)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(HomeChamfer(cut: 4, corners: .antiDiagonal).fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.75)],
                                                                                        startPoint: .top, endPoint: .bottom)))
            .fixedSize()
    }
}

// MARK: - リスト

private struct HomeQuickLinkRow: View {
    let link: HomeQuickLink
    let compact: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let tint = HomeStyle.tint(link)
        let badge = link.badge(profile: app.profile)
        let subtitle = link.subtitle(profile: app.profile)
        Button {
            FlowFX.tap(app)
            app.router.push(link.route)
        } label: {
            HStack(spacing: 8) {
                HomeGlyphTile(symbol: link.symbol, tint: tint, size: compact ? 32 : 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.title)
                        .font(HomeFont.tech(13))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(subtitle)
                        .font(HomeFont.label(9.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .homePanel(cut: 7, tint: tint, opacity: 0.6, accent: false)
            .overlay(alignment: .topTrailing) { FlowCountBadge(count: badge).offset(x: 4, y: -4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(link.title + "、" + subtitle + (badge > 0 ? L("、受取可能 \(badge)", ", \(badge) to claim") : ""))
        .accessibilityIdentifier(link.identifier)
    }
}
