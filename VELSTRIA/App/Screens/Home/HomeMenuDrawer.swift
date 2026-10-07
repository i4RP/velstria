import SwiftUI
import VelstriaCore

// 担当: home-chrome。ヘッダーの ≡ で右から開くメニュー（暗幕 + アイコンタイルのグリッド）。
// 項目を押すとドロワーを閉じてから遷移する（onSelect に遷移先を渡す。nil = 閉じるだけ）。

struct HomeMenuDrawer: View {
    let metrics: HomeMetrics
    let onSelect: (Route?) -> Void
    @Environment(AppModel.self) private var app
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = metrics
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .accessibilityHidden(true)
            panel
                .frame(width: m.drawerWidth, height: m.size.height)
                .offset(x: shown ? 0 : m.drawerWidth)
        }
        .frame(width: m.size.width, height: m.size.height)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.08)) { shown = true }
        }
    }

    private var panel: some View {
        let m = metrics
        let trailingInset = m.size.width - m.contentMaxX
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MENU")
                    .font(HomeFont.serif(18))
                    .tracking(3)
                    .foregroundStyle(HomeStyle.goldGradient)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .homePanel(cut: 6, corners: .all, tint: Theme.cyan, opacity: 0.8, accent: false)
                        .frame(width: HomeMetrics.minTapSize, height: HomeMetrics.minTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomePressStyle(scale: 0.9))
                .accessibilityLabel(L("閉じる", "Close"))
                .accessibilityIdentifier("home_menu_close")
            }
            HomeEdgeLine().frame(maxWidth: .infinity)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(HomeMenuItem.allCases) { item in
                        tile(item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12 + trailingInset)
        .padding(.top, max(10, m.safeArea.top + 8))
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                LinearGradient(colors: [HomeStyle.inkRaised.opacity(0.97), HomeStyle.ink.opacity(0.98)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [HomeStyle.violet.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LinearGradient(colors: [Theme.cyan.opacity(0), Theme.cyan, Theme.gold, Theme.cyan, Theme.cyan.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 1.5)
                .shadow(color: Theme.cyan, radius: 4)
        }
    }

    private func tile(_ item: HomeMenuItem) -> some View {
        let badge = item.badge(profile: app.profile)
        return Button {
            FlowFX.tap(app)
            onSelect(item.route)
        } label: {
            VStack(spacing: 4) {
                HomeGlyphTile(symbol: item.symbol, tint: Theme.cyan, size: 36)
                Text(item.title)
                    .font(HomeFont.label(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .homePanel(cut: 7, tint: Theme.cyan, opacity: 0.5, accent: false)
            .overlay(alignment: .topTrailing) { FlowCountBadge(count: badge).offset(x: 3, y: -3) }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.94))
        .accessibilityLabel(item.title + (badge > 0 ? L("、受取可能 \(badge)", ", \(badge) to claim") : ""))
        .accessibilityIdentifier(item.identifier)
    }

    private func close() {
        FlowFX.back(app)
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { shown = false }
        onSelect(nil)
    }
}
