import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI032 リザルト（+ UI033 評価 / UI034 通報シート）。閉じるで onClose。

/// UI032 リザルト（+ UI033 評価 / UI034 通報シート）。閉じるで onClose。
struct MatchResultView: View {
    let outcome: BattleOutcome
    let report: RewardReport
    let onClose: () -> Void

    private enum ResultTab: Hashable { case result, evaluation, rewards }

    @Environment(AppModel.self) private var app
    @State private var tab: ResultTab = .result
    @State private var bannerIn = false
    @State private var showReport = false
    @State private var closing = false

    private var summary: MatchSummary { outcome.summary }

    /// 左パネルに出す選手（人間。観戦では試合 MVP）。
    private var focus: PlayerSummary? {
        summary.humanPlayer ?? summary.players.first { $0.isMVP } ?? summary.players.max { $0.mvpScore < $1.mvpScore }
    }

    private var bannerKind: ResultBanner.Kind {
        if outcome.launch.replay != nil { return .replay }
        if outcome.launch.config.mode == .spectate { return .spectate }
        switch summary.humanWon {
        case true?: return .victory
        case false?: return .defeat
        case nil: return .ended
        }
    }

    private var canPlayAgain: Bool {
        let mode = outcome.launch.config.mode
        return outcome.launch.replay == nil && (mode == .standard || mode == .ranked)
    }

    var body: some View {
        ZStack {
            StarfieldBackground()
            RadialGradient(colors: [bannerKind.color.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.1), startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
            VStack(spacing: 6) {
                ResultBanner(kind: bannerKind, appeared: bannerIn)
                HStack(alignment: .top, spacing: 12) {
                    if let focus {
                        FocusPanel(player: focus, isSpectating: outcome.launch.isSpectating, appeared: bannerIn)
                            .frame(width: 204)
                    }
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            subheader
                            Spacer(minLength: 6)
                            FlowTabBar(items: [
                                .init(tab: ResultTab.result, title: L("結果", "Results"), symbol: "tablecells", identifier: "result_tab_result"),
                                .init(tab: ResultTab.evaluation, title: L("評価", "Rating"), symbol: "star.leadinghalf.filled", identifier: "result_tab_eval"),
                                .init(tab: ResultTab.rewards, title: L("報酬", "Rewards"), symbol: "gift.fill", identifier: "result_tab_rewards"),
                            ], selection: $tab)
                        }
                        ScrollView {
                            Group {
                                switch tab {
                                case .result: MatchScoreTable(summary: summary)
                                case .evaluation: EvaluationTab(player: focus, summary: summary)
                                case .rewards: RewardsTab(report: report, outcome: outcome)
                                }
                            }
                            .padding(.bottom, 8)
                            .transition(.opacity)
                        }
                        .scrollIndicators(.visible)
                    }
                }
                .frame(maxHeight: .infinity)
                buttons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showReport) {
            MatchReportSheet(outcome: outcome).environment(app)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.1)) { bannerIn = true }
            switch bannerKind {
            case .victory:
                app.audio.play(.victory)
                app.audio.playMusic(.victory)
                app.haptics.success()
            case .defeat:
                app.audio.play(.defeat)
                app.audio.playMusic(.defeat)
            case .ended, .spectate, .replay:
                app.audio.playMusic(.menu)
            }
        }
    }

    /// モード・試合時間・終了理由（キル数は成績表の各チーム見出しに表示）。
    private var subheader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(outcome.launch.replay != nil ? L("リプレイ", "Replay") : FlowText.mode(summary.mode))
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
                Label(FlowText.duration(summary.duration), systemImage: "clock")
                    .font(Theme.mono(12))
                    .fixedSize()
                    .accessibilityLabel(L("試合時間 \(FlowText.duration(summary.duration))", "Duration \(FlowText.duration(summary.duration))"))
            }
            HStack(spacing: 6) {
                Text(FlowText.endReason(summary.endReason))
                if outcome.launch.isSpectating, let w = summary.winner {
                    dot
                    Text(L("\(FlowText.team(w))の勝利", "\(FlowText.team(w)) wins")).foregroundStyle(Theme.gold)
                }
            }
            .font(Theme.body(11))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Theme.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private var dot: some View { Text("·").foregroundStyle(Theme.textSecondary.opacity(0.6)) }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                FlowFX.tap(app)
                showReport = true
            } label: {
                Label(L("通報・不具合報告", "Report"), systemImage: "exclamationmark.bubble.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(minHeight: 44)
            .accessibilityIdentifier("result_report")
            Spacer()
            if canPlayAgain {
                Button(action: playAgain) {
                    Label(L("もう一度", "Play Again"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .disabled(closing)
                .accessibilityIdentifier("result_again")
            }
            Button(action: close) {
                Text(L("閉じる", "Close")).frame(minWidth: 120)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(closing)
            .accessibilityIdentifier("result_close")
        }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        FlowFX.confirm(app)
        app.audio.playMusic(.menu)
        onClose()
    }

    /// 閉じた後、同じモードで対戦フローを開き直す。
    private func playAgain() {
        guard !closing else { return }
        closing = true
        FlowFX.confirm(app)
        let config = outcome.launch.config
        let entry: MatchFlowIntent.Entry
        if config.mode == .ranked {
            entry = .ranked
        } else {
            let humanTeam = config.humanSlot?.team ?? .blue
            let enemy = config.players.first { $0.team != humanTeam && $0.controller == .bot }?.botDifficulty ?? app.profile.preferredDifficulty
            entry = .standard(enemy)
        }
        app.audio.playMusic(.menu)
        onClose()
        MatchFlowIntent.present(entry, app: app, delay: .milliseconds(700))
    }
}

// MARK: - バナー

struct ResultBanner: View {
    enum Kind {
        case victory, defeat, ended, spectate, replay

        var title: String {
            switch self {
            case .victory: return "VICTORY"
            case .defeat: return "DEFEAT"
            case .ended: return Loc.isEnglish ? "MATCH OVER" : "試合終了"
            case .spectate: return L("観戦終了", "SPECTATING OVER")
            case .replay: return L("リプレイ", "REPLAY")
            }
        }

        var subtitle: String {
            switch self {
            case .victory: return L("勝利", "You won")
            case .defeat: return L("敗北", "You lost")
            case .ended: return L("勝敗なし", "No result")
            case .spectate: return L("AI 同士の対戦", "AI vs AI")
            case .replay: return L("再生終了", "Playback finished")
            }
        }

        var color: Color {
            switch self {
            case .victory: return Theme.gold
            case .defeat: return Color(red: 0.85, green: 0.32, blue: 0.45)
            case .ended, .replay: return Theme.cyan
            case .spectate: return Color(red: 0.62, green: 0.55, blue: 1.0)
            }
        }
    }

    let kind: Kind
    let appeared: Bool

    var body: some View {
        ZStack {
            // 光の帯
            LinearGradient(colors: [.clear, kind.color.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 44)
                .scaleEffect(x: appeared ? 1 : 0.1, y: 1)
                .blur(radius: 6)
            HStack(spacing: 16) {
                FourPointStar().fill(kind.color).frame(width: 18, height: 18)
                    .rotationEffect(.degrees(appeared ? 0 : -180))
                VStack(spacing: 0) {
                    Text(kind.title)
                        .font(.system(size: 40, weight: .black, design: .serif))
                        .tracking(appeared ? 6 : 24)
                        .foregroundStyle(LinearGradient(colors: [.white, kind.color], startPoint: .top, endPoint: .bottom))
                        .shadow(color: kind.color.opacity(0.8), radius: 14)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(kind.subtitle)
                        .font(Theme.heading(12))
                        .tracking(4)
                        .foregroundStyle(kind.color)
                }
                FourPointStar().fill(kind.color).frame(width: 18, height: 18)
                    .rotationEffect(.degrees(appeared ? 0 : 180))
            }
            .scaleEffect(appeared ? 1 : 1.7)
            .opacity(appeared ? 1 : 0)
        }
        .frame(height: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) \(kind.subtitle)")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("result_banner")
    }
}

// MARK: - 左: 注目選手

private struct FocusPanel: View {
    let player: PlayerSummary
    let isSpectating: Bool
    let appeared: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = player.score
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        HeroPortraitView(heroID: player.heroID, size: 62, showsRole: false)
                            .glowPulse(Theme.gold.opacity(player.isMVP ? 1 : 0.4), radius: 12)
                        GradeBadge(grade: player.grade, size: 30)
                            .offset(x: 10, y: 8)
                            .scaleEffect(appeared ? 1 : 2.5)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(duration: 0.6, bounce: 0.45).delay(0.5), value: appeared)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if isSpectating {
                            Text(L("試合 MVP", "Match MVP")).font(Theme.heading(11)).foregroundStyle(Theme.gold)
                        }
                        Text(player.displayName)
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(app.master.hero(player.heroID).map { MasterText.hero($0) } ?? player.heroID)
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if player.isMVP { MVPBadge() }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
                HStack(alignment: .firstTextBaseline) {
                    Text(FlowText.kda(s.kills, s.deaths, s.assists))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("KDA \(String(format: "%.2f", s.kda))")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.cyan)
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: 4) {
                    statRow("Lv", "\(player.level)")
                    statRow("CS", "\(s.creepScore)")
                    statRow(L("ゴールド", "Gold"), FlowText.compactNumber(s.goldEarned))
                    statRow(L("与ダメージ", "Damage"), FlowText.compactNumber(s.damageToHeroes))
                    statRow(L("タワー破壊", "Towers"), "\(s.towersDestroyed)")
                }
                .padding(8)
                .glass(cornerRadius: 10)
            }
            .padding(10)
        }
        .glass(cornerRadius: 16, tint: Theme.gold.opacity(0.6))
        .accessibilityElement(children: .contain)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - UI033 評価

private struct EvaluationTab: View {
    let player: PlayerSummary?
    let summary: MatchSummary
    @Environment(AppModel.self) private var app

    var body: some View {
        if let player {
            let won = summary.winner != nil && summary.winner == player.team
            let breakdown = MVPBreakdown.make(player, won: won)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    FlowSectionTitle(title: L("MVP スコア内訳", "MVP Score Breakdown"), symbol: "function")
                    ForEach(breakdown.lines.indices, id: \.self) { i in
                        let line = breakdown.lines[i]
                        HStack(spacing: 6) {
                            Text(line.label)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 4)
                            Text(line.detail)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(String(format: "%+.1f", line.value))
                                .font(Theme.mono(12))
                                .foregroundStyle(line.value < 0 ? Theme.danger : (line.value > 0 ? Theme.success : Theme.textSecondary))
                                .frame(width: 52, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Divider().overlay(Theme.panelStroke)
                    HStack {
                        Text(L("合計", "Total")).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f", breakdown.total)).font(Theme.mono(15)).foregroundStyle(Theme.gold)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .glass(cornerRadius: 14)

                VStack(alignment: .leading, spacing: 10) {
                    teamRanking(player)
                    gradeLegend(player)
                    advice(player)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            FlowEmptyState(symbol: "star.slash", title: L("評価データがありません", "No rating data"))
        }
    }

    private func teamRanking(_ player: PlayerSummary) -> some View {
        let team = summary.players.filter { $0.team == player.team }.sorted { $0.mvpScore == $1.mvpScore ? $0.entityID < $1.entityID : $0.mvpScore > $1.mvpScore }
        let maxScore = max(1, team.map(\.mvpScore).max() ?? 1)
        return VStack(alignment: .leading, spacing: 5) {
            FlowSectionTitle(title: L("チーム内順位", "Team Ranking"), symbol: "list.number")
            ForEach(Array(team.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 6) {
                    Text("\(i + 1)").font(Theme.mono(11)).foregroundStyle(Theme.textSecondary).frame(width: 14)
                    HeroPortraitView(heroID: p.heroID, size: 22, showsRole: false)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(p.id == player.id ? Theme.gold : Theme.cyan.opacity(0.7))
                                .frame(width: max(4, geo.size.width * CGFloat(max(0, p.mvpScore) / maxScore)))
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%.1f", p.mvpScore)).font(Theme.mono(10)).foregroundStyle(Theme.textPrimary).frame(width: 36, alignment: .trailing)
                    GradeBadge(grade: p.grade, size: 18)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(i + 1). \(p.displayName) \(String(format: "%.1f", p.mvpScore)) \(p.grade)")
            }
        }
        .padding(10)
        .glass(cornerRadius: 14)
    }

    private func gradeLegend(_ player: PlayerSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowSectionTitle(title: L("評価の決まり方", "How Grades Work"), symbol: "questionmark.circle")
            Text(L("評価はチーム内の MVP スコア順位と KDA から決まります。", "Grades come from your MVP score rank within your team and your KDA."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                legend("S", L("最高の活躍", "Outstanding"))
                legend("A", L("優秀", "Great"))
                legend("B", L("標準", "Solid"))
                legend("C", L("伸びしろ", "Room to grow"))
            }
        }
        .padding(10)
        .glass(cornerRadius: 14)
    }

    private func legend(_ g: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            GradeBadge(grade: g, size: 18)
            Text(text).font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func advice(_ player: PlayerSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowSectionTitle(title: L("次の試合へのヒント", "Tips for Next Time"), symbol: "lightbulb.fill")
            ForEach(MVPBreakdown.advice(player, durationMinutes: summary.duration / 60), id: \.self) { a in
                Label {
                    Text(a).font(Theme.body(11)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sparkle").foregroundStyle(Theme.gold)
                }
            }
        }
        .padding(10)
        .glass(cornerRadius: 14)
    }
}

// MARK: - 報酬

private struct RewardsTab: View {
    let report: RewardReport
    let outcome: BattleOutcome
    @Environment(AppModel.self) private var app
    @State private var shownCoins = 0
    @State private var shownBonus = 0
    @State private var xpValue: Double = 0
    @State private var shownLevel = 1
    @State private var levelUp = false
    @State private var shownRank: RankState?
    @State private var started = false

    var body: some View {
        if report.noRewards {
            FlowEmptyState(symbol: "gift", title: L("この試合は報酬の対象外です", "No rewards for this match"),
                           message: L("練習場・チュートリアル・観戦・リプレイでは報酬を獲得できません。", "Practice, tutorial, spectating and replays don't grant rewards."))
                .frame(minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    rewardCell(symbol: "star.circle.fill", tint: Theme.gold, title: L("試合報酬", "Match reward"), value: "+\(shownCoins)")
                    if report.firstWinBonus > 0 {
                        rewardCell(symbol: "sun.max.fill", tint: Theme.gold, title: L("初勝利ボーナス", "First win bonus"), value: "+\(shownBonus)")
                    }
                    if report.passXP > 0 {
                        rewardCell(symbol: "bolt.fill", tint: Color(red: 1.0, green: 0.62, blue: 0.3), title: L("スターパス XP", "Star Pass XP"),
                                   value: "+\(report.passXP)")
                    }
                }
                accountSection
                if let before = report.rankBefore, let after = report.rankAfter {
                    rankSection(before: before, after: after)
                }
                if !report.missionsProgressed.isEmpty { missionsSection }
                if !report.achievementsUnlocked.isEmpty { achievementsSection }
                if report.replaySaved {
                    Label(L("この試合のリプレイを保存しました（戦績・リプレイから再生）", "Replay saved — watch it from Match History or Replays"),
                          systemImage: "play.rectangle.fill")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.cyan)
                }
            }
            .onAppear(perform: start)
        }
    }

    private func rewardCell(symbol: String, tint: Color, title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title).font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 74)
        .glass(cornerRadius: 12, tint: tint.opacity(0.6))
        .accessibilityElement(children: .combine)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                FlowSectionTitle(title: L("アカウント経験値", "Account XP"), symbol: "person.fill.badge.plus")
                Text("+\(report.accountXP) XP").font(Theme.mono(12)).foregroundStyle(Theme.cyan)
            }
            HStack(spacing: 8) {
                Text("Lv.\(shownLevel)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .contentTransition(.numericText())
                FlowProgressBar(value: xpValue, tint: Theme.cyan, height: 8)
                if levelUp {
                    Text("LEVEL UP!")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.gold))
                        .glowPulse(Theme.gold, radius: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(10)
        .glass(cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("アカウント経験値 +\(report.accountXP)、レベル \(report.accountLevelAfter)", "Account XP +\(report.accountXP), level \(report.accountLevelAfter)")
                            + (report.accountLevelAfter > report.accountLevelBefore ? L("、レベルアップ", ", level up") : ""))
    }

    private func rankSection(before: RankState, after: RankState) -> some View {
        let shown = shownRank ?? before
        let change = rankChangeText(before: before, after: after)
        return HStack(spacing: 12) {
            FlowSectionTitle(title: L("ランク", "Rank"), symbol: "crown.fill")
                .fixedSize()
            RankEmblemView(tier: shown.tier, size: 40)
                .id(shown.tier)
                .transition(.scale.combined(with: .opacity))
            VStack(alignment: .leading, spacing: 3) {
                Text(RankService.displayName(shown)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary)
                if shown.tier == .starRingSovereign {
                    Text("\(shown.points) pt").font(Theme.mono(12)).foregroundStyle(Theme.gold).contentTransition(.numericText())
                } else {
                    RankStarsView(stars: shown.stars, size: 15)
                }
            }
            Spacer()
            Text(change.text)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(change.color)
        }
        .padding(10)
        .glass(cornerRadius: 12, tint: change.color.opacity(0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ランク \(RankService.displayName(after))、\(change.text)", "Rank \(RankService.displayName(after)), \(change.text)"))
    }

    private func rankChangeText(before: RankState, after: RankState) -> (text: String, color: Color) {
        let b = RankService.rating(before), a = RankService.rating(after)
        if after.tier > before.tier || (after.tier == before.tier && after.division < before.division) {
            return (L("昇格！", "PROMOTED!"), Theme.gold)
        }
        if after.tier < before.tier || (after.tier == before.tier && after.division > before.division) {
            return (L("降格", "Demoted"), Theme.danger)
        }
        if after.tier == .starRingSovereign {
            let d = after.points - before.points
            return (d >= 0 ? "+\(d) pt" : "\(d) pt", d >= 0 ? Theme.success : Theme.danger)
        }
        let d = after.stars - before.stars
        if d > 0 { return ("★ +\(d)", Theme.success) }
        if d < 0 { return ("★ \(d)", Theme.danger) }
        return (a == b ? L("変動なし", "No change") : "±0", Theme.textSecondary)
    }

    private var missionsSection: some View {
        let p = app.profile
        return VStack(alignment: .leading, spacing: 5) {
            FlowSectionTitle(title: L("ミッション進行", "Mission Progress"), symbol: "checklist")
            ForEach(report.missionsProgressed, id: \.self) { id in
                let def = LiveOpsService.missionDef(id: id)
                let prog = (p.missions.daily + p.missions.weekly).first { $0.id == id }
                HStack(spacing: 8) {
                    Image(systemName: (prog.map { $0.progress >= (def?.target ?? Int.max) } ?? false) ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .foregroundStyle(Theme.success)
                    Text(def.map { L($0.titleJa, $0.titleEn) } ?? id)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let def, let prog {
                        Text("\(min(prog.progress, def.target))/\(def.target)").font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .glass(cornerRadius: 12)
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowSectionTitle(title: L("実績解除", "Achievements Unlocked"), symbol: "trophy.fill")
            ForEach(report.achievementsUnlocked, id: \.self) { id in
                let def = LiveOpsService.achievements.first { $0.id == id }
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                    Text(def.map { L($0.titleJa, $0.titleEn) } ?? id)
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let def, def.rewardGems > 0 {
                        AttachmentChip(attachment: MailAttachment(kind: .gem, amount: def.rewardGems))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .glass(cornerRadius: 12, tint: Theme.gold.opacity(0.6))
    }

    /// 報酬の演出（コインのカウントアップ → XP バー → ランクの星）。
    private func start() {
        guard !started else { return }
        started = true
        let required = { (lv: Int) in Double(max(1, FlowAccountXP.required(forLevel: lv))) }
        let xpNow = app.profile.accountXP
        let leveled = report.accountLevelAfter > report.accountLevelBefore
        let xpBefore = FlowAccountXP.xpBefore(levelBefore: report.accountLevelBefore, levelAfter: report.accountLevelAfter,
                                              xpAfter: xpNow, gained: report.accountXP)
        shownLevel = report.accountLevelBefore
        xpValue = Double(xpBefore) / required(report.accountLevelBefore)
        shownRank = report.rankBefore
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.9)) {
                shownCoins = report.coins
                shownBonus = report.firstWinBonus
            }
            app.audio.play(.gold)
            try? await Task.sleep(for: .milliseconds(500))
            if leveled {
                withAnimation(.easeInOut(duration: 0.6)) { xpValue = 1 }
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
                    shownLevel = report.accountLevelAfter
                    levelUp = true
                }
                app.audio.play(.levelUp)
                app.haptics.success()
                xpValue = 0
                withAnimation(.easeOut(duration: 0.6)) { xpValue = Double(xpNow) / required(report.accountLevelAfter) }
            } else {
                withAnimation(.easeOut(duration: 0.8)) { xpValue = Double(xpNow) / required(report.accountLevelAfter) }
            }
            try? await Task.sleep(for: .milliseconds(700))
            if let after = report.rankAfter {
                withAnimation(.spring(duration: 0.6, bounce: 0.35)) { shownRank = after }
                if let before = report.rankBefore, RankService.rating(after) > RankService.rating(before) {
                    app.audio.play(.reward)
                }
            }
        }
    }
}

// MARK: - UI034 通報・不具合報告

struct MatchReportSheet: View {
    let outcome: BattleOutcome
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var category: SupportReportCategory = .bug
    @State private var message = ""
    @State private var mailFailed = false

    static let maxLength = 1000

    private var body_: String {
        SupportMail.body(category: category, message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                         summary: outcome.summary, launch: outcome.launch, systemVersion: UIDevice.current.systemVersion)
    }

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 10) {
                HStack {
                    Label(L("通報・不具合報告", "Report a Problem"), systemImage: "exclamationmark.bubble.fill")
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    FlowCloseButton(identifier: "report_close") { dismiss() }
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        FlowSectionTitle(title: L("種類", "Category"))
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(SupportReportCategory.allCases) { c in
                                    Button {
                                        FlowFX.tap(app)
                                        category = c
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: c.symbol).frame(width: 20)
                                            Text(c.title).font(Theme.heading(13)).lineLimit(1)
                                            Spacer(minLength: 0)
                                            if category == c { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                                        }
                                        .foregroundStyle(category == c ? Color.black.opacity(0.85) : Theme.textPrimary)
                                        .padding(.horizontal, 10)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(category == c ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Color.white.opacity(0.07))))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(category == c ? .isSelected : [])
                                    .accessibilityIdentifier("report_cat_\(c.rawValue)")
                                }
                            }
                        }
                    }
                    .frame(width: 190)

                    VStack(alignment: .leading, spacing: 8) {
                        FlowSectionTitle(title: L("内容", "Details"), trailing: "\(message.count)/\(Self.maxLength)")
                        TextEditor(text: $message)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 90)
                            .glass(cornerRadius: 12)
                            .overlay(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text(L("発生した状況や気づいた点を入力してください", "Describe what happened"))
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(14)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onChange(of: message) { _, v in
                                if v.count > Self.maxLength { message = String(v.prefix(Self.maxLength)) }
                            }
                            .accessibilityIdentifier("report_text")
                        Label(L("メールアプリで \(FeatureFlags.supportEmail) 宛の下書きを作成します。試合情報（モード・シード・時間・端末）が添付され、名前やプレイヤー ID は含まれません。",
                                "This opens a draft to \(FeatureFlags.supportEmail) in Mail with match info (mode, seed, duration, device). Your name and player ID are not included."),
                              systemImage: "envelope.fill")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button(action: send) {
                                Label(L("メールで送信", "Send via Mail"), systemImage: "paperplane.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("report_send")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
        .alert(L("メールアプリを開けませんでした", "Couldn't Open Mail"), isPresented: $mailFailed) {
            Button(L("内容をコピー", "Copy Report")) {
                UIPasteboard.general.string = "To: \(FeatureFlags.supportEmail)\n\(SupportMail.subject(category: category))\n\n\(body_)"
                app.showToast(L("コピーしました", "Copied"))
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("\(FeatureFlags.supportEmail) 宛に内容を送ってください。", "Please send the report to \(FeatureFlags.supportEmail)."))
        }
    }

    private func send() {
        guard let url = SupportMail.url(to: FeatureFlags.supportEmail, subject: SupportMail.subject(category: category), body: body_) else {
            mailFailed = true
            return
        }
        FlowFX.confirm(app)
        openURL(url) { accepted in
            if accepted {
                app.showToast(L("ご報告ありがとうございます", "Thanks for your report"))
                dismiss()
            } else {
                mailFailed = true
            }
        }
    }
}
