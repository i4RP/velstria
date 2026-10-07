import SwiftUI
import VelstriaCore

// 担当: home-chrome。ホームのフッター: タブ（ホーム / ヒーロー / 装備 / ルーン / バッグ）と、右下の対戦開始ボタン。

struct HomeFooter: View {
    let metrics: HomeMetrics
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = metrics
        HStack(spacing: 0) {
            ForEach(Array(HomeTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Theme.cyan.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1, height: m.footerBarHeight * 0.55)
                }
                tabButton(tab)
            }
        }
        .homePlaced(in: m.tabsRect)
    }

    private func tabButton(_ tab: HomeTab) -> some View {
        let selected = tab == .home
        return Button {
            guard let route = tab.route else { return }
            FlowFX.tap(app)
            app.router.push(route)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(selected ? Theme.gold : Theme.cyan)
                    .shadow(color: (selected ? Theme.gold : Theme.cyan).opacity(0.8), radius: selected ? 5 : 2)
                Text(tab.title)
                    .font(HomeFont.tech(10.5))
                    .tracking(Loc.isEnglish ? 1 : 0)
                    .foregroundStyle(selected ? HomeStyle.goldLight : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alignment: .bottom) {
                if selected {
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [Theme.gold.opacity(0.0), Theme.gold.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                        Capsule().fill(Theme.gold).frame(width: 28, height: 2).shadow(color: Theme.gold, radius: 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.92))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(tab.identifier)
    }
}

// MARK: - 対戦開始

/// 右下の大きなボタン。上段に現在ランクの星、中央に「対戦開始」、右にランクの記章。金〜橙のエネルギー感。
/// 真上に本日の初勝利ボーナスのチップ。
struct HomeStartButton: View {
    let metrics: HomeMetrics
    let now: Date
    let animated: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = metrics
        let rank = app.profile.rank
        let firstWin = HomeBadges.firstWinAvailable(app.profile, now: now)
        let shape = HomeChamfer(cut: 16, corners: [.topLeading, .bottomTrailing, .topTrailing])
        ZStack(alignment: .topLeading) {
            firstWinChip(available: firstWin)
                .homePlaced(in: m.firstWinChipRect)

            Button {
                FlowFX.confirm(app)
                MatchFlowIntent.present(nil, app: app)
            } label: {
                ZStack {
                    HomeGlow(shape: shape, color: HomeStyle.ember, radius: 14, animated: animated)
                    shape.fill(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold, HomeStyle.ember, HomeStyle.goldDeep],
                                              startPoint: .top, endPoint: .bottom))
                    // 斜めの縞（エネルギーの流れ）
                    HomeStripes()
                        .fill(Color.white.opacity(0.12))
                        .clipShape(shape)
                    if animated { HomeSheen(period: 3.2, tint: .white).clipShape(shape) }
                    shape.strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                    label(rank: rank)
                }
                .contentShape(shape)
            }
            .buttonStyle(HomePressStyle(scale: 0.96))
            .accessibilityLabel(L("対戦開始", "Battle"))
            .accessibilityIdentifier("home_play")
            .homePlaced(in: m.startRect)
        }
    }

    private func label(rank: RankState) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                // 現在のランクの星（最上位ティアは星の代わりにポイント）
                Group {
                    if rank.tier == .starRingSovereign {
                        Text("\(rank.points) pt").font(HomeFont.tech(9)).foregroundStyle(HomeStyle.onGold)
                    } else {
                        HStack(spacing: 2) {
                            ForEach(0..<RankService.maxStars, id: \.self) { i in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(i < rank.stars ? Color.white : HomeStyle.onGold.opacity(0.3))
                                    .shadow(color: i < rank.stars ? .white : .clear, radius: 2)
                            }
                        }
                    }
                }
                .accessibilityHidden(true)
                Text(L("対戦開始", "BATTLE"))
                    .font(HomeFont.italic(Loc.isEnglish ? 30 : 27))
                    .foregroundStyle(HomeStyle.onGold)
                    .shadow(color: .white.opacity(0.6), radius: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Loc.isEnglish ? "START · 5v5 vs AI" : "START · 5v5 対AI")
                    .font(HomeFont.tech(9.5))
                    .tracking(1.5)
                    .foregroundStyle(HomeStyle.onGold.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            RankEmblemView(tier: rank.tier, size: 40)
                .shadow(color: .black.opacity(0.35), radius: 3)
                .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }

    private func firstWinChip(available: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: available ? "sun.max.fill" : "checkmark.circle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(available ? Theme.gold : Theme.success)
            Text(available ? L("本日の初勝利ボーナス +300", "First win of the day +300") : L("初勝利ボーナス獲得済み", "First-win bonus claimed"))
                .font(HomeFont.label(9.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(LinearGradient(colors: [.clear, HomeStyle.ink.opacity(0.8), HomeStyle.ink.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

/// 斜めの縞模様。
private struct HomeStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = 14
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + 5, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + 5 + rect.height, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.closeSubpath()
            x += step
        }
        return p
    }
}
