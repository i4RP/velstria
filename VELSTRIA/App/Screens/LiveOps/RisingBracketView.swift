import SwiftUI
import VelstriaCore

// 担当: ui-liveops。ライジング: 対 AI の勝ち上がりラダー。
// 現ステージに挑戦 → 勝てば次へ進み段階報酬を得る。進行は Profile.rising に永続化。
// 戦闘から戻ってきたら lastOutcome を見て 1 度だけブラケットを進める（launch.id で冪等化）。

struct RisingBracketView: View {
    @Environment(AppModel.self) private var app
    @State private var heroID: String?
    @State private var processedLaunchID: UUID?

    var body: some View {
        let selected = heroID ?? PracticeSetup.defaultHeroID(profile: app.profile, master: app.master)
        ScreenScaffold(title: L("ライジング", "Rising")) {
            VStack(spacing: 12) {
                ladderPanel
                controlBar(selected: selected)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear { processResultIfNeeded() }
    }

    // MARK: ラダー

    private var ladderPanel: some View {
        let progress = app.profile.rising
        return Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("勝ち上がりラダー", "Climb the Ladder"))
                        .font(Theme.heading(15)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(RisingService.isComplete(progress)
                         ? L("踏破", "Complete")
                         : L("ステージ \(progress.stageIndex + 1)/\(RisingService.stageCount)",
                             "Stage \(progress.stageIndex + 1)/\(RisingService.stageCount)"))
                        .font(Theme.body(12)).foregroundStyle(Theme.gold)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RisingService.ladder) { stage in
                            stageNode(stage, progress: progress)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func stageNode(_ stage: RisingService.Stage, progress: RisingProgress) -> some View {
        let cleared = stage.index < progress.stageIndex
        let current = stage.index == progress.stageIndex
        let tint: Color = cleared ? Theme.success : (current ? Theme.gold : Theme.textSecondary)
        return VStack(spacing: 5) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 44, height: 44)
                Circle().stroke(tint.opacity(current ? 0.9 : 0.5), lineWidth: current ? 2 : 1).frame(width: 44, height: 44)
                if cleared {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .black)).foregroundStyle(tint)
                } else {
                    Text("\(stage.index + 1)").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                }
            }
            Label(LiveOpsFormat.difficultyName(stage.enemyDifficulty), systemImage: FlowText.difficultySymbol(stage.enemyDifficulty))
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textSecondary)
                .labelStyle(.titleAndIcon).lineLimit(1).fixedSize()
            HStack(spacing: 3) {
                Image(systemName: "star.circle.fill").foregroundStyle(Theme.gold)
                Text("\(stage.rewardCoins)")
                if stage.rewardGems > 0 {
                    Image(systemName: "diamond.fill").foregroundStyle(Theme.cyan)
                    Text("\(stage.rewardGems)")
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1).fixedSize()
        }
        .padding(8)
        .frame(width: 92)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(current ? Theme.gold.opacity(0.12) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(current ? Theme.gold.opacity(0.6) : Theme.panelStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rising_stage_\(stage.index)")
    }

    // MARK: 操作

    private func controlBar(selected: String) -> some View {
        let progress = app.profile.rising
        let complete = RisingService.isComplete(progress)
        return Panel(padding: 10) {
            HStack(spacing: 12) {
                heroStrip(selected: selected)
                Spacer(minLength: 4)
                if complete {
                    Label(L("全ステージ踏破", "All stages cleared"), systemImage: "trophy.fill")
                        .font(Theme.heading(13)).foregroundStyle(Theme.gold).lineLimit(1).fixedSize()
                } else {
                    Button {
                        challenge(heroID: selected)
                    } label: {
                        Label(L("挑戦", "Challenge"), systemImage: "flag.checkered")
                            .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                    .accessibilityIdentifier("rising_challenge")
                }
            }
        }
    }

    private func heroStrip(selected: String) -> some View {
        let owned = app.master.heroes.filter { app.owns(heroID: $0.heroID) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(owned) { hero in
                    Button {
                        app.audio.play(.uiTap)
                        heroID = hero.heroID
                    } label: {
                        HeroPortraitView(heroID: hero.heroID, size: 42)
                            .overlay(RoundedRectangle(cornerRadius: 42 * 0.2, style: .continuous)
                                .stroke(hero.heroID == selected ? Theme.gold : .clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MasterText.hero(hero))
                    .accessibilityAddTraits(hero.heroID == selected ? .isSelected : [])
                    .accessibilityIdentifier("rising_hero_\(hero.heroID)")
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: 360)
    }

    private func challenge(heroID: String) {
        guard let stage = RisingService.currentStage(app.profile.rising) else { return }
        app.audio.play(.uiConfirm)
        let config = RisingService.config(for: stage, heroID: heroID, profile: app.profile,
                                          seed: RisingService.newSeed(), master: app.master)
        app.startBattle(BattleLaunch(config: config, countsForRank: false, context: .rising(stageIndex: stage.index)))
    }

    private func processResultIfNeeded() {
        guard let outcome = app.lastOutcome, case .rising(let stageIndex) = outcome.launch.context,
              outcome.launch.id != processedLaunchID else { return }
        processedLaunchID = outcome.launch.id
        let won = outcome.summary.humanWon == true
        var p = app.profile
        if let stage = RisingService.resolve(won: won, stageIndex: stageIndex, profile: &p) {
            app.profile = p
            app.showToast(L("ステージ \(stage.index + 1) クリア！報酬を獲得しました。",
                            "Stage \(stage.index + 1) cleared! Reward granted."))
        }
    }
}
