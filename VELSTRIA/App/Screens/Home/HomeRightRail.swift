import SwiftUI
import VelstriaCore

// 担当: home-chrome。ホームの右レール: ゲームモードのカード（縦スクロール）+ オンライン / 観戦 / リプレイの行、
// 左端の取っ手で畳める（畳むとレールは右へ退き、取っ手だけ中身の右端に残る）。

struct HomeRightRail: View {
    let metrics: HomeMetrics
    @Binding var collapsed: Bool
    let animated: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// モード一覧の下に、まだ見えていないカードがあるか。
    @State private var hasMoreBelow = true

    var body: some View {
        let m = metrics
        ZStack(alignment: .topLeading) {
            VStack(spacing: m.spacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: m.modeCardSpacing) {
                        ForEach(HomeMode.allCases) { mode in
                            HomeModeCard(mode: mode, animated: animated)
                                .frame(height: m.modeSlotHeight - m.modeCardSpacing)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.containerSize.height < g.contentSize.height - 8
                } action: { _, more in
                    hasMoreBelow = more
                }
                .frame(height: m.modeListHeight)
                .overlay(alignment: .bottom) {
                    if hasMoreBelow { moreHint }
                }
                HomeSocialRow()
                    .frame(height: m.socialRowHeight)
            }
            .homePlaced(in: m.rightRailRect)
            .offset(x: collapsed ? m.railCollapseOffset : 0)
            .opacity(collapsed ? 0 : 1)
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)

            handle
                .position(x: m.handleRect.midX + (collapsed ? m.handleCollapseOffset : 0), y: m.handleRect.midY)
        }
    }

    /// 一覧の続きがあることを示す下向きの印（スクロールで末尾まで来たら消える）。
    private var moreHint: some View {
        Image(systemName: "chevron.compact.down")
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(Theme.cyan)
            .shadow(color: Theme.cyan, radius: 4)
            .padding(.horizontal, 14)
            .background(Capsule().fill(HomeStyle.ink.opacity(0.85)))
            .offset(y: 7)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var handle: some View {
        let m = metrics
        return Button {
            FlowFX.tap(app)
            withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12)) { collapsed.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(collapsed ? 180 : 0))
                .frame(width: m.handleRect.width, height: m.handleRect.height)
                .background(HomeHandleShape().fill(LinearGradient(colors: [HomeStyle.inkRaised.opacity(0.9), HomeStyle.ink.opacity(0.9)],
                                                                 startPoint: .top, endPoint: .bottom)))
                .overlay(HomeHandleShape().stroke(Theme.cyan.opacity(0.8), lineWidth: 1))
                .shadow(color: Theme.cyan.opacity(0.5), radius: 4)
                .frame(width: m.handleRect.width + 26, height: m.handleRect.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.92))
        .accessibilityLabel(collapsed ? L("モード一覧を開く", "Show modes") : L("モード一覧を畳む", "Hide modes"))
        .accessibilityIdentifier("home_rail_toggle")
    }
}

// MARK: - モードカード

/// ワイヤーフレームのユーザーカードと同じ構造: 左に丸いメダリオン、題名、状態ドット + 補足、右に小さな記章。
private struct HomeModeCard: View {
    let mode: HomeMode
    let animated: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let tint = HomeStyle.tint(mode)
        let featured = mode == .ranked
        let subtitle = mode.subtitle(profile: app.profile)
        Button {
            if mode.startsMatch { FlowFX.confirm(app) } else { FlowFX.tap(app) }
            switch mode.action(difficulty: app.profile.preferredDifficulty) {
            case .match(let entry): MatchFlowIntent.present(entry, app: app)
            case .push(let route): app.router.push(route)
            }
        } label: {
            GeometryReader { geo in
                let h = geo.size.height
                HStack(spacing: 8) {
                    medallion(tint: tint, size: min(h - 8, 44))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.title)
                            .font(HomeFont.tech(13.5))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(mode.startsMatch ? Theme.success : tint)
                                .frame(width: 6, height: 6)
                                .shadow(color: mode.startsMatch ? Theme.success : tint, radius: 2)
                            Text(subtitle)
                                .font(HomeFont.label(9.5))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                    insignia(tint: tint)
                }
                .padding(.horizontal, 6)
                .frame(width: geo.size.width, height: h)
            }
            .homePanel(cut: 9, tint: tint, opacity: featured ? 0.78 : 0.62, highlighted: featured, accent: featured)
            .overlay {
                if featured && animated { HomeSheen(period: 4.5, tint: HomeStyle.goldLight.opacity(0.5)).clipShape(HomeChamfer(cut: 9)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title + "、" + subtitle)
        .accessibilityIdentifier(mode.identifier)
    }

    private func medallion(tint: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [tint.opacity(0.85), tint.opacity(0.25), HomeStyle.ink], center: .init(x: 0.5, y: 0.35),
                                         startRadius: 1, endRadius: size * 0.6))
            Circle().stroke(LinearGradient(colors: [HomeStyle.goldLight, tint.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.3)
            Image(systemName: mode.symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: tint, radius: 3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 右端の記章（対戦を直接始めるモードは ▶、それ以外は ›）。
    private func insignia(tint: Color) -> some View {
        Image(systemName: mode.startsMatch ? "play.fill" : "chevron.right")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(mode.startsMatch ? HomeStyle.onGold : tint)
            .frame(width: 22, height: 22)
            .background(HomeChamfer(cut: 5, corners: .all).fill(mode.startsMatch ? AnyShapeStyle(HomeStyle.goldGradient) : AnyShapeStyle(tint.opacity(0.14))))
            .overlay(HomeChamfer(cut: 5, corners: .all).stroke(tint.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - ソーシャル行

private struct HomeSocialRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeSocialLink.visible()) { link in
                Button {
                    FlowFX.tap(app)
                    app.router.push(link.route)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: link.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: HomeStyle.violet, radius: 3)
                        Text(link.title)
                            .font(HomeFont.label(9))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .homePanel(cut: 6, corners: .all, tint: HomeStyle.violet, opacity: 0.66, accent: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomePressStyle(scale: 0.94))
                .accessibilityLabel(link.title)
                .accessibilityIdentifier(link.identifier)
            }
        }
    }
}
