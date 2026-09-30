import SwiftUI
import VelstriaCore

// 担当: battle-hud。チュートリアルの指示カード（上部中央）と完了カード。
// 操作部品の強調（脈動リング）は各部品が TutorialDirector.highlight を見て表示する。

struct HUDTutorialCard: View {
    let director: TutorialDirector
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Theme.gold.opacity(0.2))
                Text(director.stepNumber.map { "\($0)" } ?? "✓")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(director.title)
                        .font(.system(size: 14 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 6)
                    if let n = director.stepNumber {
                        Text("\(n)/\(TutorialDirector.stepCount)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Text(director.instruction)
                    .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                if let p = director.progress {
                    HStack(spacing: 6) {
                        ProgressView(value: p)
                            .tint(Theme.gold)
                        if let t = director.progressText {
                            Text(t)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 330 * min(scale, 1.1))
        .hudGlass(cornerRadius: 14, tint: Theme.gold.opacity(0.7))
        .shadow(color: Theme.gold.opacity(0.25), radius: 10)
        .id(director.step)
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
        .animation(.spring(duration: 0.35), value: director.step)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tutorial_card")
    }
}

struct HUDTutorialComplete: View {
    let model: HUDModel
    let director: TutorialDirector
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Theme.gold, radius: 14)
                    .scaleEffect(appeared ? 1 : 0.4)
                Text(director.title)
                    .font(Theme.title(28))
                    .foregroundStyle(.white)
                Text(director.instruction)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                Label(director.rewardNote, systemImage: "star.circle.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.gold.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1))
                Button { model.finishTutorial() } label: {
                    Label(L("ホームへ戻る", "Back to Home"), systemImage: "house.fill").frame(minWidth: 200)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("tutorial_finish")
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.07, green: 0.08, blue: 0.18).opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1.2))
            .shadow(color: Theme.gold.opacity(0.3), radius: 24)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.35)) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorial_complete")
    }
}
