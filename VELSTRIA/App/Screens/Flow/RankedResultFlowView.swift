import SwiftUI
import VelstriaCore

// 担当: ui-flow。ランク戦の試合後の流れ（Mobile Legends と同じ順番）:
// 1. 勝敗バナー（VICTORY / DEFEAT。タップして進める）は試合内の HUDEndOfMatchView
// 2. ランク: 左にスターポイント、中央に紋章・星・ティア名・段位、右に保護ポイント（星の増減を演出）→「シェア」「続ける」
// 3. 評価: 試合評価（0〜16）とメダル（MatchMedal。MLBB の条件）、6 軸のレーダー（タップで進む）
// 4. スコアボード: 両チーム 5 人の KDA・アイテム・ゴールド・メダルと評価点。顔を押すと簡単なプレイヤーカード。
//    「データ」で従来の詳しいリザルト、「クイックチャット」は定型文だけ（味方の AI が返す。通信はしない）
// 5. 「終了」→「チームを離れてロビーに戻りますか？」→ OK でホーム。「ルームに戻る」はランク戦の準備へ。
// 「シェア」は今の画面を画像にして共有シートへ（ResultShare。MatchResultView.swift に共用の部品）。

struct RankedResultFlowView: View {
    let outcome: BattleOutcome
    let report: RewardReport
    let onClose: () -> Void

    private enum Step { case rank, evaluation, scoreboard }

    @Environment(AppModel.self) private var app
    @State private var step: Step = .rank
    @State private var showsDetail = false
    @State private var confirmsLeave = false
    @State private var closing = false

    private var summary: MatchSummary { outcome.summary }
    private var won: Bool { report.won && !report.abandonedLoss }

    var body: some View {
        ZStack {
            switch step {
            case .rank:
                RankedStarsStep(before: report.rankBefore ?? app.profile.rank, after: report.rankAfter ?? app.profile.rank,
                                delta: report.rankDelta ?? RankMatchDelta(), won: won) { advance(.evaluation) }
                    .transition(.opacity)
            case .evaluation:
                RankedEvaluationStep(summary: summary, rating: report.matchRating, won: won) { advance(.scoreboard) }
                    .transition(.opacity)
            case .scoreboard:
                RankedScoreboardStep(summary: summary, won: won,
                                     onData: { showsDetail = true },
                                     onLeave: { confirmsLeave = true },
                                     onRoom: backToRoom)
                    .transition(.opacity)
            }
            if confirmsLeave { leaveDialog }
            // 戦闘の全画面表示ではルートのトーストが隠れるため、ここにも重ねる
            ToastOverlay()
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .fullScreenCover(isPresented: $showsDetail) {
            MatchResultView(outcome: outcome, report: report) { showsDetail = false }
        }
        .onAppear {
            app.audio.play(won ? .victory : .defeat)
            app.audio.playMusic(.result)
        }
        .task(id: step) {
            guard DebugLaunch.autoAdvance else { return }
            try? await Task.sleep(for: .seconds(5))
            switch step {
            case .rank: step = .evaluation
            case .evaluation: step = .scoreboard
            case .scoreboard: confirmsLeave = true
            }
        }
    }

    private func advance(_ next: Step) {
        FlowFX.tap(app)
        step = next
    }

    private var leaveDialog: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(L("お知らせ", "Notice")).font(Theme.heading(15)).foregroundStyle(Theme.textPrimary)
                Text(L("チームを離れてロビーに戻りますか？", "Leave the team and return to the lobby?"))
                    .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 24) {
                    MLButton(title: L("キャンセル", "Cancel"), style: .blue) { confirmsLeave = false }
                    MLButton(title: "OK", style: .gold) { close() }
                        .accessibilityIdentifier("ranked_leave_ok")
                }
            }
            .padding(18)
            .frame(width: 380, height: 210)
            .background(LinearGradient(colors: [Color(red: 0.10, green: 0.17, blue: 0.33), Color(red: 0.06, green: 0.10, blue: 0.22)],
                                       startPoint: .top, endPoint: .bottom))
            .overlay(Rectangle().stroke(Color(red: 0.45, green: 0.62, blue: 0.95).opacity(0.6), lineWidth: 1))
        }
        .transition(.opacity)
    }

    private func close() {
        guard !closing else { return }
        closing = true
        FlowFX.confirm(app)
        app.audio.playMusic(.menu)
        onClose()
    }

    private func backToRoom() {
        guard !closing else { return }
        closing = true
        FlowFX.confirm(app)
        app.audio.playMusic(.menu)
        onClose()
        MatchFlowIntent.present(.ranked, app: app, delay: .milliseconds(700))
    }
}

// MARK: - 共通

/// 星空と雲の背景（ランク・評価・スコアボード）。
private struct SkyBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.30), Color(red: 0.16, green: 0.24, blue: 0.55),
                                    Color(red: 0.36, green: 0.42, blue: 0.70)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.25), .clear], center: .bottom, startRadius: 10, endRadius: 520)
            Canvas { ctx, size in
                var rng = SplitMix64(seed: 7)
                for _ in 0..<90 {
                    let x = Double(rng.nextInt(in: 0...1000)) / 1000 * size.width
                    let y = Double(rng.nextInt(in: 0...1000)) / 1000 * size.height * 0.6
                    let r = Double(rng.nextInt(in: 5...18)) / 10
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.7)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 中央の縦長の結晶（紋章の台座）。
private struct CrystalShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - r.width * 0.32, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.32, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.42))
        p.closeSubpath()
        return p
    }
}

private struct Crystal: View {
    var body: some View {
        CrystalShape()
            .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.85, blue: 1.0).opacity(0.55), Color(red: 0.25, green: 0.45, blue: 0.90).opacity(0.25)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(CrystalShape().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
            .shadow(color: Color.cyan.opacity(0.5), radius: 18)
    }
}

/// MLBB 風の平たいボタン。title が空なら記号だけ（呼ぶ側で accessibilityLabel を付ける）。
struct MLButton: View {
    enum Style { case blue, gold, dark }
    let title: String
    var symbol: String? = nil
    var style: Style = .blue
    var width: CGFloat = 150
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                if !title.isEmpty {
                    Text(title).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .font(Theme.heading(14))
            .foregroundStyle(style == .gold ? Color(red: 0.28, green: 0.16, blue: 0.02) : .white)
            .frame(width: width, height: 34)
            .background(background)
            .overlay(Rectangle().stroke(style == .gold ? Color(red: 1, green: 0.95, blue: 0.7) : Color.white.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        switch style {
        case .blue:
            return LinearGradient(colors: [Color(red: 0.35, green: 0.70, blue: 0.95), Color(red: 0.18, green: 0.45, blue: 0.80)], startPoint: .top, endPoint: .bottom)
        case .gold:
            return LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.45), Color(red: 0.90, green: 0.66, blue: 0.18)], startPoint: .top, endPoint: .bottom)
        case .dark:
            return LinearGradient(colors: [Color(red: 0.10, green: 0.10, blue: 0.10), Color(red: 0.20, green: 0.18, blue: 0.12)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private func titleWord(_ won: Bool) -> String { won ? "VICTORY" : "DEFEAT" }

// MARK: - 2. ランク（星）

private struct RankedStarsStep: View {
    let before: RankState
    let after: RankState
    let delta: RankMatchDelta
    let won: Bool
    let onNext: () -> Void
    @Environment(AppModel.self) private var app
    @State private var shown: RankState?
    @State private var protShown = 0
    @State private var done = false

    var body: some View {
        let r = shown ?? before
        ZStack {
            SkyBackdrop()
            GeometryReader { geo in
                let h = geo.size.height
                ZStack {
                    Crystal()
                        .frame(width: min(300, h * 0.62), height: h * 1.05)
                        .position(x: geo.size.width / 2, y: h * 0.45)
                    VStack(spacing: 8) {
                        RankEmblemView(tier: r.tier, size: h * 0.30)
                            .id(r.tier)
                            .transition(.scale.combined(with: .opacity))
                        starsRow(r)
                        Text(RankService.shortName(r))
                            .font(Theme.heading(22))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.15, green: 0.22, blue: 0.48).opacity(0.85))
                        if r.tier != .mythic {
                            Text(RankService.roman(r.division))
                                .font(.system(size: 30, weight: .bold, design: .serif))
                                .foregroundStyle(Color(red: 0.75, green: 0.85, blue: 0.95))
                        }
                    }
                    .position(x: geo.size.width / 2, y: h * 0.48)
                    HStack {
                        // 満タンはティアごと（RankService.starPointCap / protectionCap。ミシックにスターポイントは無い）
                        pointsPanel(symbol: "star.fill", tint: Theme.gold, title: L("スターポイント", "Star Points"),
                                    value: r.tier == .mythic ? 0 : (shown == nil ? before.starPoints : after.starPoints),
                                    cap: RankService.starPointCap(r.tier),
                                    gain: won ? delta.starPointsGain : 0,
                                    lines: [(L("100%達成でスター+1", "100% grants +1 star"), nil)])
                        Spacer()
                        pointsPanel(symbol: "shield.fill", tint: Color(red: 0.95, green: 0.78, blue: 0.35), title: L("保護ポイント", "Protection Points"),
                                    value: protShown,
                                    cap: RankService.protectionCap(r.tier),
                                    gain: won ? 0 : delta.scoreBonus + delta.activeBonus,
                                    lines: [(L("100%になると、次回敗北時にスター保護が発生する", "At 100%, your next loss won't cost a star"), nil)]
                                        + (won ? [] : [(L("今回のスコアボーナス", "Score bonus"), "+\(delta.scoreBonus)"),
                                                       (L("積極的対戦ボーナス", "Active play bonus"), "+\(delta.activeBonus)")])
                                        + (delta.protected ? [(L("スター保護が発動した", "Star protection activated"), nil)] : []))
                    }
                    .padding(.horizontal, 60)
                    .position(x: geo.size.width / 2, y: h * 0.47)
                }
            }
            if done {
                HStack(spacing: 14) {
                    // 今の画面（ランクの星）を画像にして共有シートへ
                    MLButton(title: L("シェア", "Share"), symbol: "square.and.arrow.up", style: .dark, width: 120) {
                        FlowFX.tap(app)
                        if !ResultShare.shareScreen() {
                            app.showToast(L("共有できませんでした", "Couldn't share"))
                        }
                    }
                    .accessibilityIdentifier("ranked_share")
                    MLButton(title: L("続ける", "Continue"), style: .gold, width: 120, action: onNext)
                        .accessibilityIdentifier("ranked_continue")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 70)
                .padding(.bottom, 18)
                .transition(.opacity)
            }
        }
        .onAppear(perform: play)
    }

    private func starsRow(_ r: RankState) -> some View {
        Group {
            if r.tier == .mythic {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.gold)
                    Text("× \(r.stars)").font(Theme.heading(20)).foregroundStyle(.white)
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<RankService.maxStars(r.tier), id: \.self) { i in
                        Image(systemName: "star.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(i < r.stars ? Theme.gold : Color(red: 0.10, green: 0.14, blue: 0.30))
                            .shadow(color: i < r.stars ? Theme.gold.opacity(0.8) : .clear, radius: 4)
                            .scaleEffect(i < r.stars ? 1 : 0.9)
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.5), value: r.stars)
    }

    /// cap はこのティアの満タン（0 = 無い。ミシックのスターポイント）。
    private func pointsPanel(symbol: String, tint: Color, title: String, value: Int, cap: Int, gain: Int,
                             lines: [(String, String?)]) -> some View {
        let ratio = RankService.progress(value, cap: cap)
        let amount = cap > 0 ? "\(value)/\(cap)" : "—"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.6), tint], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.heading(15)).foregroundStyle(.white)
                    HStack(spacing: 0) {
                        Text(amount).foregroundStyle(.white)
                        if gain > 0 { Text("+\(gain)").foregroundStyle(Theme.gold) }
                        Spacer()
                        Text("\(Int(ratio * 100))%").foregroundStyle(.white)
                    }
                    .font(Theme.mono(11))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.4))
                            Rectangle().fill(Color(red: 1, green: 0.92, blue: 0.45))
                                .frame(width: g.size.width * CGFloat(ratio))
                        }
                    }
                    .frame(height: 4)
                }
            }
            ForEach(lines.indices, id: \.self) { i in
                HStack {
                    Text(lines[i].0)
                    Spacer()
                    if let v = lines[i].1 { Text(v).foregroundStyle(Theme.gold) }
                }
                .font(Theme.body(10.5))
                .foregroundStyle(Color(red: 0.75, green: 0.85, blue: 1.0))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 220, height: 170)
        .background(Color(red: 0.12, green: 0.18, blue: 0.40).opacity(0.75))
        .animation(.easeOut(duration: 0.8), value: value)
    }

    private func play() {
        protShown = before.protectionPoints
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = after }
            protShown = after.protectionPoints
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation { done = true }
        }
    }
}

// MARK: - 3. 評価

private struct RankedEvaluationStep: View {
    let summary: MatchSummary
    let rating: Double
    let won: Bool
    let onNext: () -> Void
    @Environment(AppModel.self) private var app
    @State private var shown = false

    private var me: PlayerSummary? { summary.humanPlayer }
    /// 自分のメダル（評価点・勝敗・チーム内の順位から。MatchMedal）。
    private var myResult: MatchMedalResult {
        me.map { MatchMedal.result(for: $0, in: summary) } ?? MatchMedalResult()
    }

    var body: some View {
        let result = myResult
        ZStack {
            SkyBackdrop()
            HStack(spacing: 18) {
                // 左: 結晶とメダル
                ZStack {
                    Crystal().frame(width: 230, height: 360)
                    VStack(spacing: 6) {
                        Text(titleWord(won))
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                        MatchMedalView(medal: result.medal, size: 110)
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("ranked_medal")
                        if let medal = result.medal {
                            Text(medal.name)
                                .font(Theme.heading(13))
                                .foregroundStyle(medal.tint)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .background(Color(red: 0.12, green: 0.18, blue: 0.40).opacity(0.7))
                    }
                    .offset(y: -30)
                }
                .scaleEffect(shown ? 1 : 0.85)
                .opacity(shown ? 1 : 0)
                // 右: プロフィールとレーダー
                VStack(alignment: .leading, spacing: 8) {
                    profileLine
                    HStack(spacing: 10) {
                        VStack(spacing: 6) {
                            RadarChart(values: radarValues, labels: radarLabels)
                                .frame(width: 250, height: 190)
                            Divider().background(Color.white.opacity(0.2))
                            if let me {
                                HStack(spacing: 10) {
                                    HeroPortraitView(heroID: me.heroID, size: 40, showsRole: false, face: true)
                                        .clipShape(Circle())
                                    MatchMedalView(medal: result.medal, size: 30)
                                    Text(FlowText.kda(me.score.kills, me.score.deaths, me.score.assists))
                                        .font(Theme.mono(13)).foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(red: 0.10, green: 0.16, blue: 0.38).opacity(0.55))
                    }
                }
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onNext)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { shown = true } }
        .accessibilityIdentifier("ranked_evaluation")
    }

    private var profileLine: some View {
        let p = app.profile
        return HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 36)).foregroundStyle(.white.opacity(0.85))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.displayName.isEmpty ? L("あなた", "You") : p.displayName).font(Theme.heading(15)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text("Lv \(p.accountLevel)").font(Theme.mono(11)).foregroundStyle(Theme.gold)
                    RankInlineView(rank: p.rank, emblemSize: 16, font: Theme.body(11))
                }
            }
        }
    }

    private let radarLabels = [L("レーニング", "Laning"), L("撃破", "Kills"), L("生存", "Survival"),
                               L("集団戦", "Teamfight"), L("ゴールド", "Gold"), "DPS"]

    /// 0〜1。試合内の最大値に対する割合。
    private var radarValues: [Double] {
        guard let me else { return Array(repeating: 0, count: 6) }
        let ps = summary.players
        func rel(_ f: (PlayerSummary) -> Double) -> Double {
            let m = ps.map(f).max() ?? 1
            return m > 0 ? max(0.08, f(me) / m) : 0.08
        }
        let teamKills = Double(max(1, summary.teamKills[me.team.rawValue]))
        return [
            rel { Double($0.score.creepScore) },
            rel { Double($0.score.kills) },
            rel { 1 / Double(1 + $0.score.deaths) },
            max(0.08, min(1, Double(me.score.kills + me.score.assists) / teamKills)),
            rel { $0.score.goldEarned },
            rel { $0.score.damageToHeroes },
        ]
    }
}

private struct RadarChart: View {
    let values: [Double]
    let labels: [String]

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let rad = min(g.size.width, g.size.height) / 2 - 22
            ZStack {
                ForEach(1...3, id: \.self) { k in
                    polygon(Array(repeating: Double(k) / 3, count: 6), c, rad)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
                polygon(values, c, rad).fill(Theme.cyan.opacity(0.55))
                polygon(values, c, rad).stroke(Theme.cyan, lineWidth: 1.5)
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(Theme.body(11))
                        .foregroundStyle(.white.opacity(0.85))
                        .position(point(i, 1.22, c, rad))
                }
            }
        }
    }

    private func point(_ i: Int, _ v: Double, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let a = -Double.pi / 2 + Double(i) * Double.pi / 3
        return CGPoint(x: c.x + CGFloat(cos(a) * v) * r, y: c.y + CGFloat(sin(a) * v) * r)
    }

    private func polygon(_ vs: [Double], _ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for i in vs.indices {
            let pt = point(i, vs[i], c, r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 4. スコアボード

private struct RankedScoreboardStep: View {
    let summary: MatchSummary
    let won: Bool
    let onData: () -> Void
    let onLeave: () -> Void
    let onRoom: () -> Void
    @Environment(AppModel.self) private var app
    @State private var liked: Set<EntityID> = []
    /// 顔を押したプレイヤー（簡単なプレイヤーカード）。
    @State private var cardPlayer: PlayerSummary?
    /// クイックチャットの定型文のメニューを開いている。
    @State private var choosesChat = false
    @State private var chat = ResultChatLog()

    private var myTeam: Team { summary.humanTeam ?? .blue }
    private var enemyTeam: Team { myTeam == .blue ? .red : .blue }

    var body: some View {
        let medals = MatchMedal.results(in: summary)
        ZStack {
            SkyBackdrop()
            Color(red: 0.04, green: 0.10, blue: 0.28).opacity(0.6).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                HStack(spacing: 4) {
                    column(myTeam, mirrored: false, medals: medals)
                    column(enemyTeam, mirrored: true, medals: medals)
                }
                .padding(.horizontal, 6)
                Spacer(minLength: 4)
                footer
            }
            .padding(.vertical, 6)
            // クイックチャットの吹き出し（下のボタン列の上）
            ResultChatFeed(log: chat)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 24)
                .padding(.bottom, 50)
        }
        .sheet(item: $cardPlayer) { p in
            ResultPlayerCard(player: p, summary: summary, showsLocalProfile: p.isHuman).environment(app)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Spacer()
            Text("\(summary.teamKills[myTeam.rawValue])")
                .font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(Color(red: 0.55, green: 0.85, blue: 1.0))
            Text(titleWord(won))
                .font(.system(size: 38, weight: .black, design: .serif))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.65)], startPoint: .top, endPoint: .bottom))
                .padding(.horizontal, 40)
            Text("\(summary.teamKills[enemyTeam.rawValue])")
                .font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.5))
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Text(L("戦闘時間 \(FlowText.duration(summary.duration))", "Duration \(FlowText.duration(summary.duration))"))
                .font(Theme.body(10)).foregroundStyle(.white.opacity(0.7)).padding(.trailing, 20).offset(y: 14)
        }
    }

    private func column(_ team: Team, mirrored: Bool, medals: [EntityID: MatchMedalResult]) -> some View {
        let tint = team == myTeam ? Color(red: 0.20, green: 0.50, blue: 0.95) : Color(red: 0.90, green: 0.25, blue: 0.35)
        return VStack(spacing: 2) {
            HStack(spacing: 14) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .black))
                Image(systemName: "skull.fill")
                Image(systemName: "hand.raised.fill")
                Text("$")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: mirrored ? .leading : .trailing)
            .padding(.horizontal, 90)
            .frame(height: 20)
            .background(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.3)], startPoint: mirrored ? .trailing : .leading,
                                       endPoint: mirrored ? .leading : .trailing))
            ForEach(summary.players.filter { $0.team == team }.sorted { $0.mvpScore > $1.mvpScore }) { p in
                row(p, mirrored: mirrored, result: medals[p.entityID] ?? MatchMedalResult())
            }
        }
    }

    private func row(_ p: PlayerSummary, mirrored: Bool, result: MatchMedalResult) -> some View {
        let s = p.score
        let name = PlayerNameRules.shown(p.displayName)
        let likeButtons = HStack(spacing: 6) {
            if !p.isHuman {
                Button { liked.insert(p.entityID); FlowFX.tap(app) } label: {
                    Image(systemName: liked.contains(p.entityID) ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 13)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Circle().stroke(Color.white.opacity(0.5)))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
        let info = VStack(alignment: mirrored ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(name).font(Theme.heading(12))
                    .foregroundStyle(p.isHuman ? Theme.gold : .white).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(s.kills)  \(s.deaths)  \(s.assists)").font(Theme.mono(11)).foregroundStyle(.white)
                Text(FlowText.compactNumber(s.goldEarned)).font(Theme.mono(11)).foregroundStyle(.white)
            }
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { i in
                    itemIcon(i < p.items.count ? p.items[i] : nil)
                }
            }
        }
        let medal = VStack(spacing: 0) {
            MatchMedalView(medal: result.medal, size: 22)
            Text(result.ratingText).font(Theme.mono(11)).foregroundStyle(.white)
        }
        .frame(width: 40)
        // 顔を押すと簡単なプレイヤーカード（第3段で名刺に置き換える）
        let face = Button {
            FlowFX.tap(app)
            cardPlayer = p
        } label: {
            HeroPortraitView(heroID: p.heroID, size: 36, showsRole: false, face: true)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    Text("\(p.level)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(name) のプレイヤー情報", "Player info: \(name)"))
        .accessibilityIdentifier("ranked_player_\(p.entityID)")
        return HStack(spacing: 6) {
            if mirrored {
                medal; info; face; likeButtons
            } else {
                likeButtons; face; info; medal
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(p.isHuman ? Color(red: 0.25, green: 0.55, blue: 0.85).opacity(0.45) : Color.black.opacity(0.15))
    }

    private func itemIcon(_ id: String?) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.35))
            if let id, let art = PortraitArt.item(id) {
                Image(uiImage: art).resizable().scaledToFill().clipShape(Circle())
            }
        }
        .frame(width: 20, height: 20)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(compact: false)
            footerRow(compact: true)
        }
        .padding(.horizontal, 20)
        // 定型文のメニューは行全体に付ける（ViewThatFits の候補ごとに付けると、同じ状態で重ねて開こうとする）
        .resultQuickChatMenu(isPresented: $choosesChat, idPrefix: "ranked_quickchat") { phrase in
            FlowFX.tap(app)
            chat.send(phrase, in: summary)
        }
    }

    /// 下のボタン列。compact は SE などの狭い画面向け（クイックチャットを記号だけにして幅を詰める）。
    private func footerRow(compact: Bool) -> some View {
        HStack(spacing: 10) {
            MLButton(title: L("データ", "Data"), symbol: "list.bullet", style: .blue, width: compact ? 110 : 130, action: onData)
                .accessibilityIdentifier("ranked_data")
            MLButton(title: compact ? "" : L("クイックチャット", "Quick Chat"), symbol: "bubble.left.fill", style: .dark,
                     width: compact ? 48 : 150) {
                FlowFX.tap(app)
                choosesChat = true
            }
            .accessibilityLabel(L("クイックチャット", "Quick Chat"))
            .accessibilityIdentifier("ranked_quickchat")
            MLButton(title: L("一括いいね", "Like All"), symbol: "hand.thumbsup.fill", style: .dark, width: compact ? 130 : 150) {
                FlowFX.tap(app)
                liked = Set(summary.players.filter { !$0.isHuman }.map(\.entityID))
            }
            Spacer()
            MLButton(title: L("終了", "Exit"), style: .blue, width: compact ? 120 : 140, action: onLeave)
                .accessibilityIdentifier("ranked_exit")
            MLButton(title: L("ルームに戻る", "Back to Room"), style: .gold, width: compact ? 140 : 150, action: onRoom)
                .accessibilityIdentifier("ranked_room")
        }
    }
}
