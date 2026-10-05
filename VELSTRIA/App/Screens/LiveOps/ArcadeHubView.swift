import SwiftUI
import VelstriaCore

// 担当: ui-liveops。アーケード: 遊べる変種モードをまとめるハブ。
// 当面は乱闘のみ。データ駆動なので変種を増やしてもここに 1 行足すだけ。

struct ArcadeHubView: View {
    @Environment(AppModel.self) private var app

    private struct ModeEntry: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
        let tint: Color
        let action: (AppModel) -> Void
    }

    private var modes: [ModeEntry] {
        [
            ModeEntry(id: "brawl", symbol: "burst.fill", title: L("乱闘", "Brawl"),
                      subtitle: L("単レーン 5v5・ジャングル無し・ゴールド/XP 加速で短時間決着。",
                                  "Single-lane 5v5, no jungle, accelerated gold/XP — fast matches."),
                      tint: Theme.gold) { app in
                MatchFlowIntent.present(.brawl(app.profile.preferredDifficulty), app: app)
            },
        ]
    }

    var body: some View {
        ScreenScaffold(title: L("アーケード", "Arcade")) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 12)], spacing: 12) {
                    ForEach(modes) { card($0) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    private func card(_ mode: ModeEntry) -> some View {
        Button {
            app.audio.play(.uiConfirm)
            app.haptics.tap()
            mode.action(app)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(mode.tint)
                    .frame(width: 54, height: 54)
                    .background(HexagonShape().fill(mode.tint.opacity(0.18)))
                    .overlay(HexagonShape().stroke(mode.tint.opacity(0.6)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title).font(Theme.title(20)).foregroundStyle(Theme.textPrimary)
                    Text(mode.subtitle)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 16, tint: mode.tint.opacity(0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("arcade_\(mode.id)")
    }
}
