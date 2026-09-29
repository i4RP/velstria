import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI036 観戦（AI 対 AI）の準備画面。

enum SpectateSetup {
    /// UI テストでは編成を固定し、スクリーンショットを安定させる。
    static let uiTestSeed: UInt64 = 20261001

    static func initialSeed() -> UInt64 {
        DebugLaunch.isUITesting ? uiTestSeed : newSeed()
    }

    /// 観戦用のシード（アプリ側の乱数。シミュレーション内の乱数は state.rng のみ）。
    static func newSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64(UInt32.max))
    }

    static func config(difficulty: Difficulty, seed: UInt64) -> MatchConfig {
        MatchFactory.botMatch(difficulty: difficulty, seed: seed)
    }

    /// チームの 5 人（ポジション順）。
    static func roster(_ config: MatchConfig, team: Team) -> [PlayerSlot] {
        config.players.filter { $0.team == team }.sorted { $0.position.rawValue < $1.position.rawValue }
    }

    /// 表示用の短いシード表記。
    static func seedLabel(_ seed: UInt64) -> String {
        String(format: "#%08X", UInt32(truncatingIfNeeded: seed))
    }
}

struct SpectateSetupView: View {
    @Environment(AppModel.self) private var app
    @State private var seed: UInt64 = SpectateSetup.initialSeed()
    @State private var difficulty: Difficulty = .normal
    @State private var didLoadPreference = false

    var body: some View {
        let config = SpectateSetup.config(difficulty: difficulty, seed: seed)
        ScreenScaffold(title: L("観戦", "Spectate")) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SpectateTeamPanel(team: .blue, roster: SpectateSetup.roster(config, team: .blue))
                    Text("VS")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Theme.gold, .white], startPoint: .top, endPoint: .bottom))
                        .fixedSize()
                        .accessibilityHidden(true)
                    SpectateTeamPanel(team: .red, roster: SpectateSetup.roster(config, team: .red))
                }
                .animation(.easeInOut(duration: 0.25), value: seed)
                controlBar(config)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear {
            guard !didLoadPreference else { return }
            didLoadPreference = true
            difficulty = app.profile.preferredDifficulty
        }
    }

    private func controlBar(_ config: MatchConfig) -> some View {
        Panel(padding: 8) {
            HStack(spacing: 10) {
                Text(L("AI 難易度", "AI Level"))
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                LiveOpsSegmented(options: Difficulty.allCases.map {
                    LiveOpsSegmentOption(value: $0, title: LiveOpsFormat.difficultyName($0), identifier: "spectate_difficulty_\($0.rawValue)")
                }, selection: $difficulty, onChange: { _ in app.audio.play(.uiTap) })
                .frame(maxWidth: 300)
                .accessibilityHint(LiveOpsFormat.difficultyDetail(difficulty))
                Spacer(minLength: 4)
                LiveOpsIconButton(symbol: "dice.fill", label: L("編成を再抽選", "Reroll teams"), tint: Theme.cyan,
                                  identifier: "spectate_reroll") {
                    app.audio.play(.uiTap)
                    app.haptics.tap()
                    seed = SpectateSetup.newSeed()
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(SpectateSetup.seedLabel(seed))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("報酬・戦績なし", "No rewards"))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .combine)
                Button {
                    start(config)
                } label: {
                    Label(L("観戦開始", "Watch"), systemImage: "eye.fill")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                .accessibilityIdentifier("spectate_start")
            }
        }
    }

    private func start(_ config: MatchConfig) {
        app.audio.play(.uiConfirm)
        app.startBattle(BattleLaunch(config: config))
    }
}

private struct SpectateTeamPanel: View {
    let team: Team
    let roster: [PlayerSlot]
    @Environment(AppModel.self) private var app

    var body: some View {
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: LiveOpsFormat.teamSymbol(team)).font(.system(size: 11, weight: .bold))
                Text(LiveOpsFormat.teamName(team)).font(Theme.heading(14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
            // 5 人を縦に等分配置（最小の 16e でもスクロールなしで収まる）
            VStack(spacing: 4) {
                ForEach(roster, id: \.position) { slot in
                    row(slot, color: color)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.20), Theme.panel], startPoint: team == .blue ? .leading : .trailing,
                                     endPoint: team == .blue ? .trailing : .leading))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectate_team_\(team == .blue ? "blue" : "red")")
    }

    private func row(_ slot: PlayerSlot, color: Color) -> some View {
        let def = app.master.hero(slot.heroID)
        return HStack(spacing: 8) {
            HeroPortraitView(heroID: slot.heroID, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(def.map { MasterText.hero($0) } ?? slot.heroID)
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(def.map { MasterText.role($0.role) } ?? "")
                    .font(Theme.body(11))
                    .foregroundStyle(def.map { Theme.roleColor($0.role) } ?? Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Text(LiveOpsFormat.positionName(slot.position))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}
