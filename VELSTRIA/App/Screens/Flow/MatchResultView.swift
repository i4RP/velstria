import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI032 リザルト（+ UI033 評価 / UI034 通報シート）。閉じるで onClose。
// 観戦・リプレイの後の操作（playAgain と同じく、閉じてから少し待って次の戦闘を開く）:
// - 「リプレイを見る」: この試合の記録（outcome.replay）をメモリからそのまま再生（保存の有無に関係なく見られる）。
// - リプレイの再生後は「もう一度再生」。AI 同士の観戦の後は「同じシードで観戦」「次の観戦」（同じマップ・難易度・新しいシード）。
// - 報酬タブ: 観戦・リプレイは報酬なし。リプレイの保存・観戦の記録・観戦の実績（Gem なし）だけを出す。
// 評価は MLBB のメダル（MatchMedal。評価点から決まる）。文字の評価（S/A/B/C）は出さない。
// 「シェア」は今の画面を画像にして共有シートへ（ResultShare）。「クイックチャット」は定型文だけ（自由入力なし）で、
// オフラインの AI 戦では吹き出しを出し、味方の AI が返す（通信はしない。オンラインは別の担当）。
// 成績表の顔を押すと簡単なプレイヤーカード（ResultPlayerCard。第3段で名刺に置き換える）。

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
    /// オンライン対戦: 通報の種類（不具合 / プレイヤー）を選ぶ。
    @State private var choosesReport = false
    @State private var moderation = ModerationPrompt()
    /// 成績表で顔を押したプレイヤー（簡単なプレイヤーカード）。
    @State private var cardPlayer: PlayerSummary?
    /// クイックチャットの定型文のメニューを開いている。
    @State private var choosesChat = false
    @State private var chat = ResultChatLog()

    private var summary: MatchSummary { outcome.summary }

    /// 全員の評価点とメダル。
    private var medals: [EntityID: MatchMedalResult] { MatchMedal.results(in: summary) }

    /// オンライン対戦の相手（自分以外の人間）。通報・ブロックの対象（ガイドライン 1.2）。
    /// プレイヤー ID・フレンドコードは、試合を始めた時に控えた座席の参加者（BattleLaunch.onlineSeatPlayers）から座席で引く。
    /// 名前では引かない（隠した名前は「プレイヤー」に揃うので、同じ名前の別人を通報・ブロックしてしまう）。控えが無ければ名前だけ。
    private var onlinePlayers: [PlayerReportTarget] {
        guard outcome.launch.isOnline, outcome.launch.replay == nil else { return [] }
        let players = outcome.launch.config.players
        let session = app.online
        let seated = outcome.launch.onlineSeatPlayers
        return players.indices.compactMap { i in
            let p = players[i]
            guard p.controller == .human, i != outcome.launch.onlineSeat else { return nil }
            let who = seated[i]
            if let who, who.peerID == session?.localPeerID { return nil }
            return PlayerReportTarget(name: PlayerNameRules.shown(p.displayName), friendCode: who?.friendCode, peerID: who?.peerID,
                                      source: .match, roomCode: session?.relayCode ?? session?.joinedRelayCode,
                                      detail: "Seed: \(summary.seed) / \(L("試合時間", "Duration")): \(FlowText.duration(summary.duration)) / \(L("座席", "Seat")): \(i + 1)",
                                      seat: i)
        }
    }

    /// 左パネルに出す選手（人間。観戦では勝ったチームの MVP のメダル、勝敗が無ければ試合 MVP）。
    private var focus: PlayerSummary? {
        if let human = summary.humanPlayer { return human }
        let results = medals
        return summary.players.first { results[$0.entityID]?.medal?.isWinnerMVP == true }
            ?? summary.players.first { $0.isMVP } ?? summary.players.max { $0.mvpScore < $1.mvpScore }
    }

    /// クイックチャット: オフラインの AI 戦に自分が出た試合だけ（観戦・リプレイ・練習場は相手がいない。オンラインは別の担当）。
    private var canQuickChat: Bool {
        let launch = outcome.launch
        guard launch.replay == nil, !launch.isOnline, !launch.isSpectating, summary.humanPlayer != nil else { return false }
        switch launch.config.mode {
        case .practice, .tutorial, .magicChess: return false
        default: return true
        }
    }

    /// プレイヤーカードにランクを出すか（この端末の人。オンライン・リプレイは座席と人が結び付かないので出さない）。
    private func isLocalPlayer(_ p: PlayerSummary) -> Bool {
        p.isHuman && !outcome.launch.isOnline && outcome.launch.replay == nil
    }

    private var bannerKind: ResultBanner.Kind {
        // リプレイを途中で止めても、成績は記録時の結果（BattleController.makeOutcome）。見出しで途中終了を示す
        if let replay = outcome.launch.replay { return outcome.abandoned ? .replayStopped(recorded: replay.summary != nil) : .replay }
        if outcome.launch.onlineSpectator { return .spectateOnline }
        // AI 同士（観戦・人間のいない乱闘 / カスタム）
        if outcome.launch.isSpectating { return .spectate }
        // 通常戦・ランク戦の途中退出は敗北として記録している
        if report.abandonedLoss { return .defeat }
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

    /// リザルトから続けて開ける戦闘（リプレイ・再観戦）。
    private enum FollowUp: Hashable {
        case watchReplay, replayAgain, sameSeed, nextSpectate
    }

    private var followUps: [FollowUp] {
        let launch = outcome.launch
        if launch.replay != nil { return [.replayAgain] }
        var list: [FollowUp] = []
        if replayLaunch != nil { list.append(.watchReplay) }
        if launch.isAllBotsOffline {
            list.append(.sameSeed)
            list.append(.nextSpectate)
        }
        return list
    }

    /// この試合のリプレイを見る起動（記録がメモリにあり、再生できる種類の試合のみ）。
    private var replayLaunch: BattleLaunch? {
        guard outcome.launch.replay == nil, let replay = outcome.replay, replay.finalTick > 0 else { return nil }
        switch outcome.launch.config.mode {
        case .practice, .tutorial, .magicChess: return nil
        default: break
        }
        // AI 同士の観戦は観戦時の速度・視界を引き継ぐ（自動カメラは既定のリプレイの扱い）
        var options = outcome.launch.isSpectating ? outcome.launch.spectatorOptions : SpectatorOptions()
        options.director = nil
        guard case .success(let launch) = ReplayLibrary.launch(replay: replay, ownerSeat: ReplayArchiveService.ownerSeat(for: outcome),
                                                               options: options) else { return nil }
        return launch
    }

    private func launch(for action: FollowUp) -> BattleLaunch? {
        let launch = outcome.launch
        switch action {
        case .watchReplay:
            return replayLaunch
        case .replayAgain:
            guard let replay = launch.replay else { return nil }
            return BattleLaunch(config: replay.config, replay: replay, replayOwnerSeat: launch.replayOwnerSeat,
                                spectatorOptions: launch.spectatorOptions)
        case .sameSeed:
            return BattleLaunch(config: launch.config, spectatorOptions: launch.spectatorOptions)
        case .nextSpectate:
            return BattleLaunch(config: SpectateSetup.nextConfig(after: launch.config, master: app.master),
                                spectatorOptions: launch.spectatorOptions)
        }
    }

    private func followUpAccessibilityLabel(_ action: FollowUp) -> String {
        switch action {
        case .watchReplay: return L("この試合のリプレイを見る", "Watch this match's replay")
        case .replayAgain: return L("リプレイをもう一度再生", "Play the replay again")
        case .sameSeed: return L("同じシードでもう一度観戦", "Watch the same seed again")
        case .nextSpectate: return L("次の AI 対戦を観戦", "Watch the next AI match")
        }
    }

    private func followUpLabel(_ action: FollowUp) -> (title: String, symbol: String, identifier: String) {
        switch action {
        case .watchReplay: return (L("リプレイ", "Replay"), "play.rectangle.fill", "result_watch_replay")
        case .replayAgain: return (L("もう一度再生", "Replay Again"), "arrow.counterclockwise", "result_replay_again")
        case .sameSeed: return (L("同じシード", "Same Seed"), "repeat", "result_same_seed")
        case .nextSpectate: return (L("次の観戦", "Next Match"), "forward.end.fill", "result_watch_next")
        }
    }

    var body: some View {
        ZStack {
            CelestialBackdrop()
            RadialGradient(colors: [bannerKind.color.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.1), startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
            VStack(spacing: 6) {
                ResultBanner(kind: bannerKind, appeared: bannerIn)
                HStack(alignment: .top, spacing: 12) {
                    if let focus {
                        // 「試合 MVP」の見出しは人間がいない観戦（MVP を表示している時）だけ。リプレイは人間の成績を出す
                        FocusPanel(player: focus, result: medals[focus.entityID] ?? MatchMedalResult(),
                                   showsMatchMVPCaption: summary.humanPlayer == nil, appeared: bannerIn)
                            .frame(width: 204)
                    }
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            subheader
                            Spacer(minLength: 6)
                            CelestialTabs(options: [
                                .init(value: ResultTab.result, title: L("結果", "Results"), symbol: "tablecells", identifier: "result_tab_result"),
                                .init(value: ResultTab.evaluation, title: L("評価", "Rating"), symbol: "star.leadinghalf.filled", identifier: "result_tab_eval"),
                                .init(value: ResultTab.rewards, title: L("報酬", "Rewards"), symbol: "gift.fill", identifier: "result_tab_rewards"),
                            ], selection: $tab, fills: false)
                        }
                        ScrollView {
                            Group {
                                switch tab {
                                case .result:
                                    MatchScoreTable(summary: summary) { p in
                                        FlowFX.tap(app)
                                        cardPlayer = p
                                    }
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
            .moderationPrompts(moderation)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            // クイックチャットの吹き出し（下のボタン列の上）
            ResultChatFeed(log: chat)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 20)
                .padding(.bottom, 60)
            // 戦闘の全画面表示ではルートのトーストが隠れるため、ここにも重ねる
            ToastOverlay()
        }
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showReport) {
            MatchReportSheet(outcome: outcome).environment(app)
        }
        .sheet(item: $cardPlayer) { p in
            ResultPlayerCard(player: p, summary: summary, showsLocalProfile: isLocalPlayer(p)).environment(app)
        }
        .onAppear {
            if outcome.launch.config.mode == .tutorial && outcome.launch.replay == nil && !app.profile.tutorialCompleted {
                app.profile.tutorialCompleted = true
            }
            withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.1)) { bannerIn = true }
            switch bannerKind {
            case .victory:
                app.audio.play(.victory)
                app.audio.playMusic(.result)
                app.haptics.success()
            case .defeat:
                app.audio.play(.defeat)
                app.audio.playMusic(.result)
            case .ended, .spectate, .spectateOnline, .replay, .replayStopped:
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

    /// 下段のボタン。幅が足りなければ通報・シェア → クイックチャット → 続きの操作の順にアイコンだけにする（SE でも 1 行に収める）。
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            buttonRow(compactTools: false, compactChat: false, compact: false)
            buttonRow(compactTools: true, compactChat: false, compact: false)
            buttonRow(compactTools: true, compactChat: true, compact: false)
            buttonRow(compactTools: true, compactChat: true, compact: true)
        }
        // オンライン対戦: 不具合の報告か、相手プレイヤーの通報（ブロックも）を選ぶ
        .confirmationDialog(L("通報・不具合報告", "Report"), isPresented: $choosesReport, titleVisibility: .visible) {
            Button(L("不具合・ご意見を報告", "Report a problem")) { showReport = true }
            ForEach(onlinePlayers) { target in
                Button(L("\(target.displayName) を通報・ブロック", "Report or block \(target.displayName)")) {
                    moderation.report = target
                }
            }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        }
        // 定型文のメニューは行全体に付ける（ViewThatFits の候補ごとに付けると、同じ状態で重ねて開こうとする）
        .resultQuickChatMenu(isPresented: $choosesChat, idPrefix: "result_quickchat") { phrase in
            FlowFX.tap(app)
            chat.send(phrase, in: summary)
        }
    }

    private func buttonRow(compactTools: Bool, compactChat: Bool, compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            Button {
                FlowFX.tap(app)
                if onlinePlayers.isEmpty {
                    showReport = true
                } else {
                    choosesReport = true
                }
            } label: {
                if compactTools {
                    Image(systemName: "exclamationmark.bubble.fill").frame(minWidth: 20)
                } else {
                    Label(L("通報・不具合報告", "Report"), systemImage: "exclamationmark.bubble.fill")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(minHeight: 44)
            .accessibilityLabel(L("通報・不具合報告", "Report"))
            .accessibilityIdentifier("result_report")
            Button(action: share) {
                if compactTools {
                    Image(systemName: "square.and.arrow.up").frame(minWidth: 20)
                } else {
                    Label(L("シェア", "Share"), systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(minHeight: 44)
            .disabled(closing)
            .accessibilityLabel(L("シェア", "Share"))
            .accessibilityIdentifier("result_share")
            if canQuickChat {
                Button {
                    FlowFX.tap(app)
                    choosesChat = true
                } label: {
                    if compactChat {
                        Image(systemName: "bubble.left.fill").frame(minWidth: 20)
                    } else {
                        Label(L("クイックチャット", "Quick Chat"), systemImage: "bubble.left.fill").lineLimit(1)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .disabled(closing)
                .accessibilityLabel(L("クイックチャット", "Quick Chat"))
                .accessibilityIdentifier("result_quickchat")
            }
            Spacer(minLength: 4)
            ForEach(followUps, id: \.self) { action in
                let label = followUpLabel(action)
                Button {
                    if let next = launch(for: action) { relaunch(next) }
                } label: {
                    if compact {
                        Image(systemName: label.symbol).frame(minWidth: 20)
                    } else {
                        Label(label.title, systemImage: label.symbol).lineLimit(1)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .disabled(closing)
                .accessibilityLabel(followUpAccessibilityLabel(action))
                .accessibilityIdentifier(label.identifier)
            }
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

    /// 今の画面を画像にして共有シートを開く。
    private func share() {
        FlowFX.tap(app)
        if !ResultShare.shareScreen() {
            app.showToast(L("共有できませんでした", "Couldn't share"))
        }
    }

    /// 閉じた後、少し待ってから次の戦闘（リプレイ・観戦）を開く（全画面表示が閉じ終わってから。playAgain と同じ流れ）。
    private func relaunch(_ next: BattleLaunch) {
        guard !closing else { return }
        closing = true
        FlowFX.confirm(app)
        app.audio.playMusic(.menu)
        onClose()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard app.activeBattle == nil else { return }
            app.startBattle(next)
        }
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
        case victory, defeat, ended, spectate, spectateOnline, replay
        /// リプレイを途中で止めた（recorded = 成績は記録時の結果。古い記録で結果が無ければ止めた時点の成績）。
        case replayStopped(recorded: Bool)

        var title: String {
            switch self {
            case .victory: return "VICTORY"
            case .defeat: return "DEFEAT"
            case .ended: return Loc.isEnglish ? "MATCH OVER" : "試合終了"
            case .spectate, .spectateOnline: return L("観戦終了", "SPECTATING OVER")
            case .replay, .replayStopped: return L("リプレイ", "REPLAY")
            }
        }

        var subtitle: String {
            switch self {
            case .victory: return L("勝利", "You won")
            case .defeat: return L("敗北", "You lost")
            case .ended: return L("勝敗なし", "No result")
            case .spectate: return L("AI 同士の対戦", "AI vs AI")
            case .spectateOnline: return L("オンライン対戦の観戦", "Online match")
            case .replay: return L("再生終了", "Playback finished")
            case .replayStopped(let recorded):
                return recorded ? L("再生を中断（記録時の結果）", "Stopped early · recorded result") : L("再生を中断", "Stopped early")
            }
        }

        var color: Color {
            switch self {
            case .victory: return Theme.gold
            case .defeat: return Color(red: 0.85, green: 0.32, blue: 0.45)
            case .ended, .replay, .replayStopped: return Theme.cyan
            case .spectate, .spectateOnline: return Color(red: 0.62, green: 0.55, blue: 1.0)
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
    /// 評価点とメダル。
    let result: MatchMedalResult
    /// 人間のいない観戦で MVP を表示している（「試合 MVP」の見出しを出す）。
    let showsMatchMVPCaption: Bool
    let appeared: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = player.score
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        HeroPortraitView(heroID: player.heroID, size: 62, showsRole: false)
                            .glowPulse(Theme.gold.opacity(result.medal?.isMVP == true ? 1 : 0.4), radius: 12)
                        // メダルを出さないモード（練習場など。評価点も無い）では何も重ねない
                        if result.rating != nil {
                            MatchMedalView(medal: result.medal, size: 36)
                                .offset(x: 12, y: 10)
                                .scaleEffect(appeared ? 1 : 2.5)
                                .opacity(appeared ? 1 : 0)
                                .animation(.spring(duration: 0.6, bounce: 0.45).delay(0.5), value: appeared)
                                .accessibilityIdentifier("result_medal")
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if showsMatchMVPCaption {
                            Text(L("試合 MVP", "Match MVP")).font(Theme.heading(11)).foregroundStyle(Theme.gold)
                        }
                        Text(PlayerNameRules.shown(player.displayName))
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(app.master.hero(player.heroID).map { MasterText.hero($0) } ?? player.heroID)
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let medal = result.medal {
                            Text(medal.name)
                                .font(Theme.heading(11))
                                .foregroundStyle(medal.tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
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
                    statRow(L("評価", "Rating"), result.ratingText)
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
                    SectionTitle(title: L("MVP スコア内訳", "MVP Score Breakdown"), symbol: "function")
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
                            // 0 × −1.5 の -0.0 を "+0.0" と表示する
                            Text(String(format: "%+.1f", line.value == 0 ? 0 : line.value))
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
                    medalLegend
                    advice(player)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            EmptyStateView(symbol: "star.slash", title: L("評価データがありません", "No rating data"))
        }
    }

    /// チーム内の順位（MVP スコア順。同点は ID 順）と評価点・メダル。
    private func teamRanking(_ player: PlayerSummary) -> some View {
        let team = summary.players(of: player.team)
        let results = MatchMedal.results(in: summary)
        return VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("チーム内順位", "Team Ranking"), symbol: "list.number")
            ForEach(Array(team.enumerated()), id: \.element.id) { i, p in
                let r = results[p.entityID] ?? MatchMedalResult()
                HStack(spacing: 6) {
                    Text("\(i + 1)").font(Theme.mono(11)).foregroundStyle(Theme.textSecondary).frame(width: 14)
                    HeroPortraitView(heroID: p.heroID, size: 22, showsRole: false)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(p.id == player.id ? Theme.gold : Theme.cyan.opacity(0.7))
                                .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, (r.rating ?? 0) / 16)))))
                        }
                    }
                    .frame(height: 8)
                    Text(r.ratingText).font(Theme.mono(10)).foregroundStyle(Theme.textPrimary).frame(width: 36, alignment: .trailing)
                    if r.rating != nil {
                        MatchMedalView(medal: r.medal, size: 22)
                    } else {
                        Color.clear.frame(width: 22, height: 22)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(i + 1). \(PlayerNameRules.shown(p.displayName)) \(L("評価", "rating")) \(r.ratingText) \(r.medal?.name ?? "")")
            }
        }
        .padding(10)
        .glass(cornerRadius: 14)
    }

    /// メダルの決まり方（MLBB の条件）。
    private var medalLegend: some View {
        let loss = MatchMedal.text(MatchMedal.Threshold.mvpLoss)
        return VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("メダルの決まり方", "How Medals Work"), symbol: "questionmark.circle")
            Text(L("試合の評価点（0〜16）でメダルが決まります。チームで評価点がいちばん高いプレイヤーは MVP（負けたチームは \(loss) 以上で敗北 MVP）です。",
                   "Your match rating (0–16) decides the medal. The top-rated player on the winning team is MVP; on the losing team, MVP Loss needs \(loss)+."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(MatchMedal.allCases, id: \.self) { m in
                HStack(spacing: 6) {
                    MatchMedalView(medal: m, size: 22)
                    Text(m.name)
                        .font(Theme.heading(11))
                        .foregroundStyle(m.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 96, alignment: .leading)
                    Text(m.condition)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.name)、\(m.condition)")
            }
        }
        .padding(10)
        .glass(cornerRadius: 14)
    }

    private func advice(_ player: PlayerSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("次の試合へのヒント", "Tips for Next Time"), symbol: "lightbulb.fill")
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
        if report.abandonedLoss {
            VStack(alignment: .leading, spacing: 10) {
                EmptyStateView(symbol: "flag.slash", title: L("途中退出のため報酬はありません", "No rewards for leaving early"),
                               message: L("試合を途中で退出したため、敗北として記録されました。", "You left the match, so it was recorded as a loss."))
                    .frame(minHeight: 150)
                if let before = report.rankBefore, let after = report.rankAfter {
                    rankSection(before: before, after: after)
                }
            }
            .onAppear { shownRank = report.rankAfter }
        } else if report.noRewards {
            VStack(alignment: .leading, spacing: 10) {
                EmptyStateView(symbol: "gift", title: L("この試合は報酬の対象外です", "No rewards for this match"),
                               message: L("練習場・チュートリアル・観戦・リプレイでは報酬を獲得できません。", "Practice, tutorial, spectating and replays don't grant rewards."))
                    .frame(minHeight: report.replaySaved || report.watchCounted ? 120 : 180)
                if report.watchCounted { watchSection }
                if !report.achievementsUnlocked.isEmpty { achievementsSection }
                if report.replaySaved { replaySavedNote }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    rewardCell(symbol: "star.circle.fill", currency: .coin, tint: Theme.gold, title: L("試合報酬", "Match reward"), value: "+\(shownCoins)")
                    if report.firstWinBonus > 0 {
                        rewardCell(symbol: "sun.max.fill", tint: Theme.gold, title: L("初勝利ボーナス", "First win bonus"), value: "+\(shownBonus)")
                    }
                    if report.passXP > 0 {
                        rewardCell(symbol: "bolt.fill", tint: Color(red: 1.0, green: 0.62, blue: 0.3), title: L("スターパス XP", "Star Pass XP"),
                                   value: "+\(report.passXP)")
                    }
                    if report.magicDust > 0 {
                        rewardCell(symbol: EmblemStyle.dustSymbol, tint: EmblemStyle.dustColor, title: L("マジックダスト", "Magic Dust"),
                                   value: "+\(report.magicDust)")
                    }
                }
                accountSection
                if let before = report.rankBefore, let after = report.rankAfter {
                    rankSection(before: before, after: after)
                }
                if !report.missionsProgressed.isEmpty { missionsSection }
                if !report.achievementsUnlocked.isEmpty { achievementsSection }
                if report.replaySaved { replaySavedNote }
            }
            .onAppear(perform: start)
        }
    }

    private var replaySavedNote: some View {
        Label(L("この試合のリプレイを保存しました（リプレイ一覧から再生・共有）", "Replay saved — watch or share it from Replays"),
              systemImage: "play.rectangle.fill")
            .font(Theme.body(11))
            .foregroundStyle(Theme.cyan)
            .accessibilityIdentifier("result_replay_saved")
    }

    /// 観戦の記録（最後まで見た観戦・リプレイ。報酬は無い）。
    private var watchSection: some View {
        let c = app.profile.career
        let isReplay = outcome.launch.replay != nil
        return HStack(spacing: 10) {
            Image(systemName: isReplay ? "play.rectangle.on.rectangle.fill" : "eye.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(isReplay ? L("リプレイを最後まで見ました", "Replay watched to the end")
                              : L("最後まで観戦しました", "Match watched to the end"))
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                Text(L("通算: 観戦 \(c.spectatedMatches) 試合 · リプレイ \(c.replaysWatched) 本",
                       "Total: \(c.spectatedMatches) matches · \(c.replaysWatched) replays"))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glass(cornerRadius: 12, tint: Theme.cyan.opacity(0.6))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result_watch_record")
    }

    private func rewardCell(symbol: String, currency: CurrencyIcon.Kind? = nil, tint: Color, title: String, value: String) -> some View {
        VStack(spacing: 3) {
            if let currency {
                CurrencyIcon(kind: currency, size: 21)
            } else {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(tint)
            }
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
                SectionTitle(title: L("アカウント経験値", "Account XP"), symbol: "person.fill.badge.plus")
                Text("+\(report.accountXP) XP").font(Theme.mono(12)).foregroundStyle(Theme.cyan)
            }
            HStack(spacing: 8) {
                Text("Lv.\(shownLevel)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .contentTransition(.numericText())
                CelestialProgressBar(value: xpValue, tint: Theme.cyan, height: 8)
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
            SectionTitle(title: L("ランク", "Rank"), symbol: "crown.fill")
                .fixedSize()
            RankEmblemView(tier: shown.tier, size: 40)
                .id(shown.tier)
                .transition(.scale.combined(with: .opacity))
            VStack(alignment: .leading, spacing: 3) {
                Text(RankService.displayName(shown)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary)
                if shown.tier == .mythic {
                    Text("★ \(shown.stars)").font(Theme.mono(12)).foregroundStyle(Theme.gold).contentTransition(.numericText())
                } else {
                    RankStarsView(stars: shown.stars, maxStars: RankService.maxStars(shown.tier), size: 15)
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
        let d = after.stars - before.stars
        if d > 0 { return ("★ +\(d)", Theme.success) }
        if d < 0 { return ("★ \(d)", Theme.danger) }
        return (a == b ? L("変動なし", "No change") : "±0", Theme.textSecondary)
    }

    private var missionsSection: some View {
        let p = app.profile
        return VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("ミッション進行", "Mission Progress"), symbol: "checklist")
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
            SectionTitle(title: L("実績解除", "Achievements Unlocked"), symbol: "trophy.fill")
            ForEach(report.achievementsUnlocked, id: \.self) { id in
                let def = LiveOpsService.achievements.first { $0.id == id }
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                    Text(def.map { L($0.titleJa, $0.titleEn) } ?? id)
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let def, def.rewardGems > 0 {
                        RewardChip(attachment: MailAttachment(kind: .gem, amount: def.rewardGems))
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

// MARK: - シェア・クイックチャット・プレイヤーカード（ランク戦のリザルトと共用）

/// 「シェア」: 今の画面をそのまま画像にして共有シート（UIActivityViewController）を開く（MLBB のリザルトのシェア）。
@MainActor
enum ResultShare {
    /// 共有シートを開けたか（画面の窓が見つからなければ false）。
    static func shareScreen() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow),
              var top = window.rootViewController else { return false }
        let bounds = window.bounds
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            _ = window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(sheet, animated: true)
        return true
    }
}

/// リザルトのクイックチャットの定型文（自由入力は無い。MLBB 日本語版の文言は未確認）。
enum ResultQuickChat: String, CaseIterable, Identifiable {
    case niceGame, wellPlayed, thanks, oneMore

    var id: String { rawValue }

    var text: String {
        switch self {
        case .niceGame: return L("ナイスゲーム！", "Nice game!")
        case .wellPlayed: return L("よくやった！", "Well played!")
        case .thanks: return L("ありがとう！", "Thank you!")
        case .oneMore: return L("もう一戦やろう！", "One more game!")
        }
    }

    var symbol: String {
        switch self {
        case .niceGame: return "hand.thumbsup.fill"
        case .wellPlayed: return "star.fill"
        case .thanks: return "heart.fill"
        case .oneMore: return "arrow.counterclockwise"
        }
    }

    /// オフラインの AI 戦で味方の AI が返す定型文。
    var reply: String {
        switch self {
        case .niceGame, .thanks: return "GG!"
        case .wellPlayed: return L("ありがとう！", "Thanks!")
        case .oneMore: return L("いいね！", "Sure!")
        }
    }
}

/// クイックチャットの吹き出し（自分の定型文と、味方の AI の返事）。数秒で消える。端末の中だけで、通信はしない。
@Observable
@MainActor
final class ResultChatLog {
    struct Line: Identifiable, Equatable {
        let id: Int
        let sender: String
        let text: String
        let mine: Bool
    }

    /// 出ている吹き出し（古い順。最大 4 つ）。
    private(set) var lines: [Line] = []
    @ObservationIgnored private var nextID = 0
    /// 送った回数（返事をする味方を順に回す）。
    @ObservationIgnored private var sent = 0

    /// 定型文を送る。自分の吹き出しを出し、味方に AI がいれば少し後にその AI の返事を出す。
    func send(_ phrase: ResultQuickChat, in summary: MatchSummary) {
        let me = summary.humanPlayer
        post(sender: me.map { PlayerNameRules.shown($0.displayName) } ?? L("あなた", "You"), text: phrase.text, mine: true)
        let mates = summary.players.filter { $0.team == me?.team && !$0.isHuman }.sorted { $0.entityID < $1.entityID }
        guard !mates.isEmpty else { return }
        let replier = PlayerNameRules.shown(mates[sent % mates.count].displayName)
        sent += 1
        let reply = phrase.reply
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.post(sender: replier, text: reply, mine: false)
        }
    }

    private func post(sender: String, text: String, mine: Bool) {
        nextID += 1
        let line = Line(id: nextID, sender: sender, text: text, mine: mine)
        withAnimation(.spring(duration: 0.3)) {
            lines.append(line)
            if lines.count > 4 { lines.removeFirst(lines.count - 4) }
        }
        let id = line.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.remove(id)
        }
    }

    private func remove(_ id: Int) {
        withAnimation(.easeOut(duration: 0.3)) {
            lines.removeAll { $0.id == id }
        }
    }
}

/// クイックチャットの吹き出しの列（画面の左下。押せない）。
struct ResultChatFeed: View {
    let log: ResultChatLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(log.lines) { line in
                HStack(spacing: 6) {
                    Text(line.sender)
                        .font(Theme.heading(11))
                        .foregroundStyle(line.mine ? Theme.gold : Celestial.ice)
                        .lineLimit(1)
                    Text(line.text)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(HomeChamfer(cut: 5).fill(Celestial.ink.opacity(0.88)))
                .overlay(HomeChamfer(cut: 5).stroke((line.mine ? Theme.gold : Celestial.ice).opacity(0.55), lineWidth: 0.7))
                .transition(.move(edge: .leading).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .allowsHitTesting(false)
    }
}

/// クイックチャットの定型文のメニュー（小さなポップオーバーの中身）。
struct ResultQuickChatMenu: View {
    /// 各定型文のボタンの accessibilityIdentifier の頭（"<idPrefix>_<rawValue>"）。
    let idPrefix: String
    let onSelect: (ResultQuickChat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("クイックチャット", "Quick Chat"))
                .font(Celestial.heading(13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            ForEach(ResultQuickChat.allCases) { phrase in
                Button {
                    onSelect(phrase)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: phrase.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Celestial.ice)
                            .frame(width: 18)
                        Text(phrase.text)
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(minWidth: 210, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(idPrefix)_\(phrase.rawValue)")
            }
        }
        .padding(.bottom, 6)
        .presentationBackground(Celestial.ink)
    }
}

extension View {
    /// クイックチャットの定型文のメニュー（ポップオーバー）。選ぶと閉じて onSend。
    func resultQuickChatMenu(isPresented: Binding<Bool>, idPrefix: String,
                             onSend: @escaping (ResultQuickChat) -> Void) -> some View {
        popover(isPresented: isPresented) {
            ResultQuickChatMenu(idPrefix: idPrefix) { phrase in
                isPresented.wrappedValue = false
                onSend(phrase)
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// 成績表の顔を押すと開く、簡単なプレイヤーカード（名前・ヒーロー・K/D/A・メダル。この端末の人はランクも）。
/// 第3段で名刺（docs/OUTGAME_GAP.md 12-1）に置き換える。
struct ResultPlayerCard: View {
    let player: PlayerSummary
    let summary: MatchSummary
    /// この端末の人（アカウントレベルとランクを出す）。AI・ほかの人は基本の情報だけ。
    var showsLocalProfile = false
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var heroName: String {
        app.master.hero(player.heroID).map { MasterText.hero($0) } ?? player.heroID
    }

    var body: some View {
        let result = MatchMedal.result(for: player, in: summary)
        let s = player.score
        ZStack {
            CelestialBackdrop()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SectionTitle(title: L("プレイヤー情報", "Player Info"), symbol: "person.text.rectangle")
                    FlowCloseButton(identifier: "result_card_close") { dismiss() }
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 6) {
                        HeroPortraitView(heroID: player.heroID, size: 96, showsRole: false)
                        Text(heroName)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 112)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(PlayerNameRules.shown(player.displayName))
                            .font(Celestial.title(22))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityIdentifier("result_card_name")
                        if showsLocalProfile {
                            HStack(spacing: 10) {
                                Text("Lv.\(app.profile.accountLevel)")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.gold)
                                RankInlineView(rank: app.profile.rank, emblemSize: 24)
                            }
                        }
                        // メダルを出さないモード（練習場など）では出さない
                        if result.rating != nil {
                            HStack(spacing: 10) {
                                MatchMedalView(medal: result.medal, size: 48)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.medal?.name ?? L("メダルなし", "No medal"))
                                        .font(Theme.heading(14))
                                        .foregroundStyle(result.medal?.tint ?? Theme.textSecondary)
                                    Text(L("評価 \(result.ratingText)", "Rating \(result.ratingText)"))
                                        .font(Theme.mono(12))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        HStack(spacing: 8) {
                            FlowStatCell(title: "K / D / A", value: FlowText.kda(s.kills, s.deaths, s.assists))
                            FlowStatCell(title: "Lv", value: "\(player.level)")
                            FlowStatCell(title: L("ゴールド", "Gold"), value: FlowText.compactNumber(s.goldEarned))
                            FlowStatCell(title: L("与ダメージ", "Damage"), value: FlowText.compactNumber(s.damageToHeroes))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .preferredColorScheme(.dark)
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
        ReportMail.body(category: category, message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                         summary: outcome.summary, launch: outcome.launch, systemVersion: UIDevice.current.systemVersion)
    }

    var body: some View {
        ZStack {
            CelestialBackdrop()
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
                        SectionTitle(title: L("種類", "Category"))
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
                        SectionTitle(title: L("内容", "Details"), trailing: "\(message.count)/\(Self.maxLength)")
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
            ToastOverlay()
        }
        .preferredColorScheme(.dark)
        .alert(L("メールアプリを開けませんでした", "Couldn't Open Mail"), isPresented: $mailFailed) {
            Button(L("内容をコピー", "Copy Report")) {
                UIPasteboard.general.string = "To: \(FeatureFlags.supportEmail)\n\(ReportMail.subject(category: category))\n\n\(body_)"
                app.showToast(L("コピーしました", "Copied"))
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("\(FeatureFlags.supportEmail) 宛に内容を送ってください。", "Please send the report to \(FeatureFlags.supportEmail)."))
        }
    }

    private func send() {
        guard let url = ReportMail.url(to: FeatureFlags.supportEmail, subject: ReportMail.subject(category: category), body: body_) else {
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
