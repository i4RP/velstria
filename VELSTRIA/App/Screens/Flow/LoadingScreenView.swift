import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI026 ロード画面（5 vs 5 のプレイヤーカード・進捗・ヒント）。準備完了で onReady を呼ぶ。

/// UI026 ロード画面。準備完了で onReady を呼ぶ。
struct LoadingScreenView: View {
    let launch: BattleLaunch
    let onReady: () -> Void

    @Environment(AppModel.self) private var app
    @State private var progress: [Double] = []
    @State private var overall: Double = 0
    @State private var tipIndex = 0
    @State private var appeared = false

    /// 最低表示時間（秒）。
    static let minimumDuration = 2.0

    private var blue: [PlayerSlot] { slots(.blue) }
    private var red: [PlayerSlot] { slots(.red) }

    private func slots(_ team: Team) -> [PlayerSlot] {
        launch.config.players.filter { $0.team == team }.sorted { $0.position.rawValue < $1.position.rawValue }
    }

    private func index(of slot: PlayerSlot) -> Int {
        launch.config.players.firstIndex(of: slot) ?? 0
    }

    /// 国旗を見せるチーム（MLBB と同じく自分の味方だけ。観戦・リプレイでは誰の国旗も出さない）。
    private var flagTeam: Team? {
        guard !launch.isSpectating else { return nil }
        if let seat = launch.onlineSeat, launch.config.players.indices.contains(seat) { return launch.config.players[seat].team }
        return launch.config.players.first { $0.controller == .human }?.team
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                // 試合前の背景（オーロラの夜空と遺跡の稜線。カードの邪魔をしない中間調。tools/portraits/cards.py と同じ Codex 生成）
                Image("LoadingBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            LinearGradient(colors: [.clear, .clear, Color.black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { geo in
                let rowHeight = max(96, min(170, (geo.size.height - 118) / 2))
                let cardWidth = max(90, min(rowHeight * 0.72, (geo.size.width - 48) / 5))
                VStack(spacing: 6) {
                    header
                    if red.isEmpty {
                        soloBody(width: min(220, geo.size.width * 0.3), height: min(260, geo.size.height - 120))
                            .frame(maxHeight: .infinity)
                    } else if blue.count == 1 && red.count == 1 {
                        duelBody(height: max(140, (geo.size.height - 110) / 2))
                    } else {
                        teamRow(blue, team: .blue, width: cardWidth, height: rowHeight)
                        vsDivider
                        teamRow(red, team: .red, width: cardWidth, height: rowHeight)
                    }
                    footer
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .persistentSystemOverlays(.hidden)
        .task { await load() }
        .onAppear {
            app.audio.playMusic(.loading)
            withAnimation(.spring(duration: 0.7, bounce: 0.2)) { appeared = true }
        }
    }

    // MARK: 見出し・フッタ

    private var title: String {
        if launch.replay != nil { return L("リプレイ再生", "Replay") }
        // 人間のいない乱闘・カスタムも観戦（見出しで「観戦」と分かるように）
        if launch.isAllBotsOffline && launch.config.mode != .spectate {
            return "\(FlowText.mode(.spectate)) · \(FlowText.mode(launch.config.mode))"
        }
        return FlowText.mode(launch.config.mode)
    }

    /// マップ名（マップは mode から導出: 乱闘は単レーンの回廊、それ以外は星環の戦場）。
    static func mapName(_ mode: MatchMode) -> String {
        mode == .brawl ? L("乱闘の回廊", "Brawl Corridor") : L("星環の戦場", "Star Ring Battlefield")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            Text(title)
                .font(Theme.title(20))
                .foregroundStyle(Theme.textPrimary)
            Text("·").foregroundStyle(Theme.textSecondary)
            Text(Self.mapName(launch.config.mode))
                .font(Theme.heading(14))
                .foregroundStyle(Theme.cyan)
                .accessibilityIdentifier("loading_map")
            Spacer()
            if launch.countsForRank {
                Label(RankService.displayName(app.profile.rank), systemImage: "crown.fill")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.gold)
            }
            Text("LOADING")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(Theme.textSecondary)
                .phaseAnimator([0.4, 1.0]) { v, a in v.opacity(a) } animation: { _ in .easeInOut(duration: 0.7) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.34), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// 色だけに頼らずチームを示す見出し（形 + 名前 + 対象の段を指す矢印。ブルーは上段、レッドは下段）。
    private func teamTag(_ team: Team) -> some View {
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        let human = launch.localTeam
        let title = human.map { $0 == team ? L("味方", "Allies") : L("敵", "Enemies") } ?? FlowText.team(team)
        return HStack(spacing: 4) {
            Image(systemName: FlowText.teamSymbol(team))
            Text(title)
            Image(systemName: team == .blue ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .heavy))
        }
        .font(Theme.heading(11))
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }

    private var vsDivider: some View {
        HStack(spacing: 12) {
            teamTag(.blue)
            Rectangle().fill(LinearGradient(colors: [.clear, Theme.teamColor(.blue, colorblind: app.profile.settings.colorblindMode)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
            Text("VS")
                .font(.system(size: 22, weight: .black, design: .serif))
                .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.gold.opacity(0.7), radius: 8)
                .scaleEffect(appeared ? 1 : 2)
                .opacity(appeared ? 1 : 0)
            Rectangle().fill(LinearGradient(colors: [Theme.teamColor(.red, colorblind: app.profile.settings.colorblindMode), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
            teamTag(.red)
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            TipCard(tip: FlowTips.all[tipIndex % FlowTips.all.count])
                .id(tipIndex)
                .transition(.opacity)
                .frame(maxWidth: 560)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int((overall * 100).rounded()))%")
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
                CelestialProgressBar(value: overall, tint: Theme.gold, height: 6)
                    .frame(width: 150)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("読み込み \(Int((overall * 100).rounded()))%", "Loading \(Int((overall * 100).rounded()))%"))
            .accessibilityIdentifier("loading_progress")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.14)))
    }

    // MARK: カード

    private func teamRow(_ list: [PlayerSlot], team: Team, width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, slot in
                let idx = index(of: slot)
                // 「あなた」はオンラインなら自分の座席、それ以外は唯一の人間（リプレイは誰も強調しない）
                LoadingPlayerCard(slot: slot, progress: progress.indices.contains(idx) ? progress[idx] : 0,
                                  highlight: !launch.isSpectating && (launch.onlineSeat.map { idx == $0 } ?? (slot.controller == .human)),
                                  showsFlag: slot.team == flagTeam, width: width, height: height)
                    .offset(y: appeared ? 0 : (team == .blue ? -30 : 30))
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(duration: 0.6, bounce: 0.2).delay(Double(i) * 0.05 + (team == .red ? 0.15 : 0)), value: appeared)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 1 対 1: 味方のカードを左上、敵のカードを右下に互い違いに置き、間にヒントの帯（MLBB の 1v1 ロード画面）。
    private func duelBody(height: CGFloat) -> some View {
        let width = height * 0.66
        return VStack(spacing: 0) {
            card(blue[0], width: width, height: height)
                .offset(x: -width * 0.55, y: appeared ? 0 : -30)
                .frame(maxWidth: .infinity)
            card(red[0], width: width, height: height)
                .offset(x: width * 0.85, y: appeared ? 0 : 30)
                .frame(maxWidth: .infinity)
        }
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.2), value: appeared)
    }

    private func card(_ slot: PlayerSlot, width: CGFloat, height: CGFloat) -> some View {
        let idx = index(of: slot)
        return LoadingPlayerCard(slot: slot, progress: progress.indices.contains(idx) ? progress[idx] : 0,
                                 highlight: !launch.isSpectating && (launch.onlineSeat.map { idx == $0 } ?? (slot.controller == .human)),
                                 showsFlag: slot.team == flagTeam, width: width, height: height)
    }

    /// 練習場・チュートリアル（1 人）。
    private func soloBody(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 24) {
            if let slot = launch.config.players.first {
                LoadingPlayerCard(slot: slot, progress: progress.first ?? 0, highlight: true, width: width, height: height)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(launch.config.mode == .tutorial ? L("基本操作を学びましょう", "Learn the basics") : L("自由に練習できます", "Practice freely"),
                      systemImage: launch.config.mode == .tutorial ? "graduationcap.fill" : "figure.run")
                    .font(Theme.heading(16))
                    .foregroundStyle(Theme.textPrimary)
                Text(launch.config.mode == .tutorial
                     ? L("画面の案内に従って、移動・攻撃・スキル・タワー攻略を体験します。", "Follow the on-screen guide to try moving, attacking, skills and towers.")
                     : L("敵ヒーローは出現しません。人形を相手にスキルやビルドを試せます。報酬はありません。", "No enemy heroes. Try skills and builds on training dummies. No rewards."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)
        }
    }

    // MARK: 進行

    /// 途中で一度だけ短く止まる進み方（x: 0〜1 の経過率、stall: 止まる位置）。
    static func stalledProgress(_ x: Double, stall: Double) -> Double {
        let pause = 0.12
        if x <= stall { return x }
        if x <= stall + pause { return stall }
        let rest = max(0.0001, 1 - stall - pause)
        return min(1, stall + (x - stall - pause) / rest * (1 - stall))
    }

    /// 各カードの読み込みを個別の速さで進め、最低表示時間を満たしたら onReady。
    private func load() async {
        let n = launch.config.players.count
        var rng = SplitMix64(seed: launch.config.seed ^ 0x10AD_5EED)
        let durations = (0..<n).map { _ in 1.0 + rng.nextDouble() * 0.9 }
        let stalls = (0..<n).map { _ in 0.3 + rng.nextDouble() * 0.4 }
        progress = Array(repeating: 0, count: n)
        tipIndex = FlowTips.startIndex(seed: launch.config.seed)
        // 実処理: 登場ヒーローのマスター参照を解決し、3D モデル（メッシュ・同梱 USDZ）を読み込んでおく
        for slot in launch.config.players {
            _ = app.master.hero(slot.heroID)
            _ = app.master.skills(forHero: slot.heroID)
        }
        // 地面テクスチャ・シェーダー（マテリアル・後処理）をメインスレッドの外で作り始める（戦闘画面は出来上がりを受け取るだけ）
        BattlePreload.begin(settings: app.profile.settings, map: MapDefinition.map(for: launch.config.mode))
        // 前の試合のテンプレートを先に捨て、読み込みは 1 tick に 1 人ずつ（まとめて読むと最初のフレームが止まる）
        let players = launch.config.players.map { (heroID: $0.heroID, skinID: $0.skinID) }
        HeroModelLibrary.purge(keepingPlayers: players, master: app.master)
        var loaded = 0
        let start = Date()
        var tipRotated = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            if loaded < players.count {
                // USDZ の読み込みはメインスレッドの外で待つ（ロード画面のアニメーションを止めない）
                await HeroModelLibrary.preloadAsync(heroID: players[loaded].heroID, skinID: players[loaded].skinID,
                                                    master: app.master)
                loaded += 1
            }
            let t = Date().timeIntervalSince(start)
            // 読み込み前のカードは 100% にしない
            progress = (0..<n).map { i in
                min(i < loaded ? 1 : 0.95, Self.stalledProgress(min(1, t / durations[i]), stall: stalls[i]))
            }
            overall = min(1, t / Self.minimumDuration)
            if !tipRotated && t > 1.1 {
                tipRotated = true
                withAnimation(.easeInOut(duration: 0.4)) { tipIndex += 1 }
            }
            if t >= Self.minimumDuration && loaded == players.count && progress.allSatisfy({ $0 >= 1 }) { break }
        }
        if Task.isCancelled { return }
        app.audio.play(.matchStart)
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }
        onReady()
    }
}

/// 試合前のヒーローカード（縦長のカード絵を平行四辺形に切り抜き、国旗・スキン名・ヒーロー名・プレイヤー名・スペル・進捗を重ねる）。
private struct LoadingPlayerCard: View {
    let slot: PlayerSlot
    let progress: Double
    let highlight: Bool
    /// 国旗を出すか（味方だけ。LoadingScreenView.flagTeam）。
    var showsFlag = true
    let width: CGFloat
    let height: CGFloat
    @Environment(AppModel.self) private var app

    /// 平行四辺形の傾き（幅に対する上辺のずれ）。
    static let slant: CGFloat = 0.1

    var body: some View {
        let color = Theme.teamColor(slot.team, colorblind: app.profile.settings.colorblindMode)
        let human = slot.controller == .human
        let hero = app.master.hero(slot.heroID)
        let skin = slot.skinID.flatMap { app.master.cosmetic($0) }
        let shape = CardSlant(slant: Self.slant)
        let font = max(9, min(15, height * 0.05))
        // 国旗: スロットに無ければ（オフライン）自分の国。CPU も同じ地域のサーバーから出る扱い
        let country = slot.countryCode ?? app.profile.countryCode
        ZStack(alignment: .bottomLeading) {
            art
                .frame(width: width, height: height)
            LinearGradient(colors: [.clear, .clear, color.opacity(0.35), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                if let skin {
                    Text(MasterText.cosmetic(skin))
                        .font(.system(size: font * 0.9, weight: .medium))
                        .foregroundStyle(Theme.rarityColor(skin.rarity))
                }
                Text(hero.map { MasterText.hero($0) } ?? slot.heroID)
                    .font(.system(size: font * 1.05, weight: .semibold))
                    .foregroundStyle(.white)
                Text(human ? PlayerNameRules.shown(slot.displayName) : "CPU")
                    .font(.system(size: font, weight: .medium))
                    .foregroundStyle(highlight ? Color(red: 0.45, green: 0.95, blue: 0.5) : .white.opacity(0.9))
                HStack(spacing: 3) {
                    ForEach(slot.spells, id: \.self) { SpellIconView(spellID: $0, size: font * 1.7) }
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: font * 0.9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(progress >= 1 ? Theme.success : .white.opacity(0.85))
                }
                .padding(.top, 2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .shadow(color: .black.opacity(0.9), radius: 2)
            .padding(.leading, width * Self.slant * 0.35 + 8)
            .padding(.trailing, 8)
            .padding(.bottom, 6)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(alignment: .topLeading) {
            if showsFlag {
                CountryFlagBadge(code: country, size: max(14, height * 0.085))
                    .padding(.leading, width * Self.slant + 6)
                    .padding(.top, 6)
            }
        }
        .overlay(shape.stroke(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                              lineWidth: highlight ? 3 : 2))
        .shadow(color: color.opacity(highlight ? 0.7 : 0.35), radius: highlight ? 10 : 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(human ? slot.displayName : "CPU") \(hero.map { MasterText.hero($0) } ?? "") \(Int((progress * 100).rounded()))%")
    }

    @ViewBuilder private var art: some View {
        if let card = PortraitArt.card(slot.heroID) {
            Image(uiImage: card).resizable().interpolation(.high).scaledToFill()
        } else {
            HeroPortraitView(heroID: slot.heroID, size: height, showsRole: false)
        }
    }
}

/// 上辺が右へずれた平行四辺形。
private struct CardSlant: Shape {
    let slant: CGFloat

    func path(in r: CGRect) -> Path {
        let d = r.width * slant
        var p = Path()
        p.move(to: CGPoint(x: r.minX + d, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - d, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
