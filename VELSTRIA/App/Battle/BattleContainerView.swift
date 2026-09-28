import SwiftUI
import VelstriaCore

// 担当: battle-renderer / battle-hud（Wave 2）。
// 現在は Wave 1 の画面フロー確認用スタブ: 戦闘をヘッドレスで高速実行して結果を返す。

struct BattleContainerView: View {
    let launch: BattleLaunch
    let onFinish: (BattleOutcome) -> Void

    @State private var progress: Double = 0
    @State private var running = false

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 18) {
                Text(L("戦闘（開発中スタブ）", "Battle (dev stub)"))
                    .font(Theme.title(24))
                    .foregroundStyle(.white)
                ProgressView(value: progress)
                    .frame(width: 320)
                HStack(spacing: 16) {
                    Button(L("高速シミュレート", "Simulate")) { simulate() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(running)
                        .accessibilityIdentifier("battle_stub_simulate")
                    Button(L("退出", "Leave")) { leave() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("battle_stub_leave")
                }
            }
        }
    }

    private func simulate() {
        running = true
        let config = launch.config
        Task.detached(priority: .userInitiated) {
            let sim = Simulation(config: config)
            let recorder = ReplayRecorder(config: config)
            sim.recorder = recorder
            var lastReport = 0.0
            while !sim.isEnded && sim.state.time < min(config.maxDuration, 25 * 60) {
                sim.step()
                if sim.state.time - lastReport > 30 {
                    lastReport = sim.state.time
                    let p = sim.state.time / (25 * 60)
                    await MainActor.run { progress = p }
                }
            }
            if !sim.isEnded { sim.abort() }
            let summary = ScoreSystem.summary(sim.state)
            let replay = recorder.finish(summary: summary)
            await MainActor.run {
                onFinish(BattleOutcome(launch: launch, summary: summary, replay: replay, abandoned: false))
            }
        }
    }

    private func leave() {
        let sim = Simulation(config: launch.config)
        sim.abort()
        onFinish(BattleOutcome(launch: launch, summary: ScoreSystem.summary(sim.state), replay: nil, abandoned: true))
    }
}
