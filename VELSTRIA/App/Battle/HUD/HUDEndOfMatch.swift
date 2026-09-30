import SwiftUI
import VelstriaCore

// 担当: battle-hud。試合終了の演出: VICTORY / DEFEAT（観戦はチーム勝利、引き分け）の大きなバナー（約 2.5 秒）、
// その後「続ける」でリザルトへ（controller.makeOutcome(abandoned: false)）。

struct HUDEndOfMatchView: View {
    let model: HUDModel
    let phase: HUDEndPhase
    let colorblind: Bool

    @State private var appeared = false
    @State private var shine = false

    var body: some View {
        let style = Self.style(phase.kind, colorblind: colorblind)
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(appeared ? 0.55 : 0))
                .ignoresSafeArea()
            RadialGradient(colors: [style.color.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 420)
                .opacity(appeared ? 1 : 0)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ZStack {
                    // 光条
                    ForEach(0..<12, id: \.self) { k in
                        Capsule()
                            .fill(LinearGradient(colors: [style.color.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top))
                            .frame(width: 6, height: 150)
                            .offset(y: -75)
                            .rotationEffect(.degrees(Double(k) * 30 + (shine ? 15 : 0)))
                    }
                    .opacity(phase.kind == .defeat ? 0.25 : 0.8)
                    Image(systemName: style.symbol)
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(LinearGradient(colors: [.white, style.color], startPoint: .top, endPoint: .bottom))
                        .shadow(color: style.color, radius: 16)
                }
                .frame(height: 110)
                Text(style.title)
                    .font(.system(size: 58, weight: .black, design: .serif))
                    .italic()
                    .tracking(6)
                    .foregroundStyle(LinearGradient(colors: [.white, style.color], startPoint: .top, endPoint: .bottom))
                    .shadow(color: style.color.opacity(0.9), radius: 18)
                    .scaleEffect(appeared ? 1 : 1.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(style.subtitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                if let reason = HUDText.endReason(phase.reason) {
                    Text(reason)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                ZStack {
                    if case .prompt = phase {
                        Button { model.continueAfterEnd() } label: {
                            Label(L("続ける", "Continue"), systemImage: "chevron.right.2").frame(minWidth: 180)
                        }
                        .buttonStyle(PrimaryButtonStyle(color: style.color))
                        .accessibilityIdentifier("result_continue")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(height: 52)
            }
            .opacity(appeared ? 1 : 0)
        }
        .animation(.spring(duration: 0.4), value: phase)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.35)) { appeared = true }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { shine = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_end")
    }

    struct Style {
        var title: String
        var subtitle: String
        var symbol: String
        var color: Color
    }

    static func style(_ kind: HUDMatchResultKind, colorblind: Bool) -> Style {
        switch kind {
        case .victory:
            return Style(title: "VICTORY", subtitle: L("勝利！ 敵の Star Core を打ち破った", "The enemy Star Core has fallen"),
                         symbol: "trophy.fill", color: Theme.gold)
        case .defeat:
            return Style(title: "DEFEAT", subtitle: L("敗北… 次の戦いに備えよう", "Defeat... regroup for the next battle"),
                         symbol: "shield.lefthalf.filled", color: Theme.danger)
        case .draw:
            return Style(title: "DRAW", subtitle: L("引き分け", "No winner this time"), symbol: "circle.dashed",
                         color: Color(red: 0.7, green: 0.72, blue: 0.85))
        case .teamWin(let team):
            return Style(title: team == .blue ? "BLUE WINS" : "RED WINS",
                         subtitle: L("\(HUDText.teamName(team)) チームの勝利", "\(HUDText.teamName(team)) team wins"),
                         symbol: "crown.fill", color: Theme.teamColor(team, colorblind: colorblind))
        }
    }
}
