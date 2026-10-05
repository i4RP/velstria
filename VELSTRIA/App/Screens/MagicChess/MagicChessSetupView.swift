import SwiftUI
import VelstriaCore

// 担当: ui（マジックチェス）。入口。AI 難易度とシードを選んで開始する。

struct MagicChessSetupView: View {
    @Environment(AppModel.self) private var app
    @State private var difficulty: Difficulty = .normal
    @State private var seed: UInt64 = UInt64.random(in: 1...UInt64(UInt32.max))

    var body: some View {
        ScreenScaffold(title: L("マジックチェス", "Magic Chess")) {
            VStack(spacing: 14) {
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("オートバトラー", "Auto Battler"), systemImage: "square.grid.3x3.fill")
                            .font(Theme.heading(15)).foregroundStyle(Theme.cyan)
                        Text(L("8 人で対戦。ゴールドでチビ英雄を買い、盤面に並べると自動で戦います。ロールのシナジーを揃え、最後まで生き残りましょう。",
                               "Face 8 players. Buy chibi heroes with gold, place them on the board and they fight automatically. Stack role synergies and be the last standing."))
                            .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Panel(padding: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("AI 難易度", "AI Level")).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                            LiveOpsSegmented(options: Difficulty.allCases.map {
                                LiveOpsSegmentOption(value: $0, title: LiveOpsFormat.difficultyName($0),
                                                     identifier: "mc_difficulty_\($0.rawValue)")
                            }, selection: $difficulty, onChange: { _ in app.audio.play(.uiTap) })
                        }
                        HStack(spacing: 10) {
                            LiveOpsIconButton(symbol: "dice.fill", label: L("シード再抽選", "Reroll seed"), tint: Theme.cyan,
                                              identifier: "mc_reroll_seed") {
                                app.audio.play(.uiTap); app.haptics.tap()
                                seed = UInt64.random(in: 1...UInt64(UInt32.max))
                            }
                            Text(MagicChessFormat.seedLabel(seed)).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 4)
                            Button {
                                start()
                            } label: {
                                Label(L("開始", "Start"), systemImage: "play.fill").lineLimit(1).fixedSize()
                            }
                            .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                            .accessibilityIdentifier("mc_start")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    private func start() {
        app.audio.play(.uiConfirm)
        let name = app.profile.displayName.isEmpty ? L("プレイヤー", "Player") : app.profile.displayName
        let config = MagicChessConfig(seed: seed, humanName: name, aiDifficulty: difficulty)
        app.startMagicChess(MagicChessLaunch(config: config))
    }
}
