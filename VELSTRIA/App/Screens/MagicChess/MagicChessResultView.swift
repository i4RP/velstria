import SwiftUI
import VelstriaCore

// 担当: ui（マジックチェス）。最終結果（順位・報酬・順位表）。

struct MagicChessResultView: View {
    @Environment(AppModel.self) private var app
    let controller: MagicChessController
    let onClose: () -> Void

    var body: some View {
        let placement = controller.human?.placement ?? max(1, controller.state.aliveCount)
        let win = placement == 1
        return HStack(spacing: 14) {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: win ? "crown.fill" : "flag.checkered")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(win ? Theme.gold : Theme.cyan)
                Text(win ? L("優勝！", "Winner!") : L("ゲーム終了", "Game Over"))
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.gold)
                Text(MagicChessFormat.placement(placement))
                    .font(Theme.heading(20))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 10) {
                    reward("star.circle.fill", "\(MagicChessRewardService.coins(placement: placement))", Theme.gold)
                    reward("arrow.up.circle.fill", "+\(MagicChessRewardService.accountXP(placement: placement)) XP", Theme.cyan)
                }
                Button { onClose() } label: {
                    Label(L("ロビーへ", "Back to Lobby"), systemImage: "house.fill").frame(maxWidth: 280, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("mc_result_close")
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .worldShellCard(selected: true)
            standings
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reward(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            if symbol == "star.circle.fill" {
                CurrencyIcon(kind: .coin, size: 17)
            } else {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Text(text).font(Theme.heading(15)).foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.panel))
    }

    private var standings: some View {
        VStack(spacing: 8) {
            SectionTitle(title: L("最終順位", "Final standings"), symbol: "list.number")
            ForEach(Array(controller.state.standings.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(Theme.mono(12)).foregroundStyle(i == 0 ? Theme.gold : Theme.textSecondary).frame(width: 20)
                    Text(p.displayName).font(Theme.body(12))
                        .foregroundStyle(p.isHuman ? Theme.gold : Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 0)
                    if p.alive {
                        Label("\(p.hp)", systemImage: "heart.fill").font(Theme.body(11)).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: 320)
            }
        }
        .padding(10)
        .worldShellCard()
    }
}
