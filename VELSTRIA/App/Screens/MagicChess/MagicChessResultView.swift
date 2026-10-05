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
        return VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: win ? "crown.fill" : "flag.checkered")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(win ? Theme.gold : Theme.cyan)
                .glowPulse(win ? Theme.gold : Theme.cyan, radius: 14)
            Text(win ? L("優勝！", "Winner!") : L("ゲーム終了", "Game Over"))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(MagicChessFormat.placement(placement))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.gold)

            HStack(spacing: 14) {
                reward("star.circle.fill", "\(MagicChessRewardService.coins(placement: placement))", Theme.gold)
                reward("arrow.up.circle.fill", "+\(MagicChessRewardService.accountXP(placement: placement)) XP", Theme.cyan)
            }

            standings
            Spacer(minLength: 0)
            Button { onClose() } label: {
                Label(L("ホームへ", "Back to Home"), systemImage: "house.fill").frame(maxWidth: 280, minHeight: 50)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("mc_result_close")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reward(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(Theme.heading(15)).foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var standings: some View {
        VStack(spacing: 4) {
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
        .glass(cornerRadius: 12)
    }
}
