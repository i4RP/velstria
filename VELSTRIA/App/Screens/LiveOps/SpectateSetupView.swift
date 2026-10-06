import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI036 観戦（AI 対 AI）の準備画面。
// - マップ（標準 / 乱闘）・チーム別の AI 難易度・枠ごとのヒーロー指定・シード（入力・コピー・再抽選）を選んで観戦を始める。
//   構成は MatchFactory.spectateMatch（標準マップは mode .spectate、乱闘は mode .brawl の全員 AI = 観戦扱い）。
// - 観戦の設定（再生速度・視界・自動カメラ・最大時間）は BattleLaunch.spectatorOptions / 構成で渡す。
// - 選択は Profile.spectatePreferences に保存し、次に開いた時に復元する（枠の指定とシードは毎回やり直す）。
// - 観戦の記録（通算・今週の目標・観戦の実績）は設定シートで見られる。観戦は報酬・戦績の対象外。

enum SpectateSetup {
    /// UI テストでは編成を固定し、スクリーンショットを安定させる。
    static let uiTestSeed: UInt64 = 20261001
    /// 最大時間の選択肢（分。0 = マップの既定）。
    static let maxMinutesChoices = [0, 10, 20, 30]

    static func initialSeed() -> UInt64 {
        DebugLaunch.isUITesting ? uiTestSeed : newSeed()
    }

    /// 観戦用のシード（アプリ側の乱数。シミュレーション内の乱数は state.rng のみ）。
    static func newSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64(UInt32.max))
    }

    /// 単一難易度・標準マップ（従来の構成。botMatch と同じ）。
    static func config(difficulty: Difficulty, seed: UInt64) -> MatchConfig {
        MatchFactory.botMatch(difficulty: difficulty, seed: seed)
    }

    /// 準備画面の選択から構成を作る。
    static func config(options: SpectateMatchOptions, seed: UInt64, master: MasterData = .shared) -> MatchConfig {
        MatchFactory.spectateMatch(options: options, seed: seed, master: master)
    }

    /// 保存済みの選択 → 構成の選択（難易度の未設定はプロフィールの既定難易度）。
    static func matchOptions(_ prefs: SpectatePreferences, preferred: Difficulty, picks: [SpectatePick]) -> SpectateMatchOptions {
        SpectateMatchOptions(map: prefs.map,
                             blueDifficulty: prefs.blueDifficulty ?? preferred,
                             redDifficulty: prefs.redDifficulty ?? preferred,
                             picks: picks,
                             maxDuration: prefs.maxMinutes > 0 ? Double(prefs.maxMinutes) * 60 : nil)
    }

    /// 観戦の初期設定（速度・視界・自動カメラ）。速度は選べる値に丸める。
    @MainActor
    static func spectatorOptions(_ prefs: SpectatePreferences) -> SpectatorOptions {
        let speed = BattleController.spectatorSpeeds.contains(prefs.speed) ? prefs.speed : 1
        return SpectatorOptions(speed: speed, vision: prefs.vision, director: prefs.director)
    }

    /// 観戦の起動パラメータ。
    @MainActor
    static func launch(config: MatchConfig, prefs: SpectatePreferences) -> BattleLaunch {
        BattleLaunch(config: config, spectatorOptions: spectatorOptions(prefs))
    }

    /// 次の観戦（リザルトから）: 同じマップ・難易度・最大時間で、新しいシード・枠の指定なし。
    static func nextConfig(after config: MatchConfig, seed: UInt64 = newSeed(), master: MasterData = .shared) -> MatchConfig {
        MatchFactory.spectateMatch(options: MatchFactory.spectateOptions(from: config), seed: seed, master: master)
    }

    /// チームの 5 人（ポジション順）。
    static func roster(_ config: MatchConfig, team: Team) -> [PlayerSlot] {
        config.players.filter { $0.team == team }.sorted { $0.position.rawValue < $1.position.rawValue }
    }

    /// 表示用のシード表記（32 bit までは 8 桁、それより大きければ 16 桁の 16 進）。
    static func seedLabel(_ seed: UInt64) -> String {
        seed <= UInt64(UInt32.max) ? String(format: "#%08X", UInt32(truncatingIfNeeded: seed))
                                   : String(format: "#%016llX", seed)
    }

    /// 入力されたシード: "#" / "0x" 付きか英字を含めば 16 進、数字だけなら 10 進。空白は無視。読めなければ nil。
    static func parseSeed(_ text: String) -> UInt64? {
        var s = text.filter { !$0.isWhitespace }
        guard !s.isEmpty else { return nil }
        var hex = false
        if s.hasPrefix("#") { s.removeFirst(); hex = true }
        if s.lowercased().hasPrefix("0x") { s.removeFirst(2); hex = true }
        guard !s.isEmpty, s.count <= 20 else { return nil }
        if !hex && s.allSatisfy(\.isNumber) { return UInt64(s, radix: 10) }
        guard s.count <= 16 else { return nil }
        return UInt64(s, radix: 16)
    }

    static func mapTitle(_ map: SpectateMap) -> String {
        map == .brawl ? L("乱闘", "Brawl") : L("標準", "Standard")
    }

    static func mapDetail(_ map: SpectateMap) -> String {
        map == .brawl ? L("乱闘の回廊（単レーン・加速）", "Brawl Corridor (1 lane, fast)")
                      : L("星環の戦場（3 レーン）", "Star Ring (3 lanes)")
    }

    static func speedTitle(_ speed: Double) -> String {
        speed < 1 ? "0.5×" : "\(Int(speed))×"
    }

    static func visionTitle(_ vision: Team?) -> String {
        switch vision {
        case .blue?: return L("ブルー視点", "Blue view")
        case .red?: return L("レッド視点", "Red view")
        default: return L("全体", "Full")
        }
    }

    static func durationTitle(_ minutes: Int) -> String {
        minutes <= 0 ? L("既定", "Default") : L("\(minutes) 分", "\(minutes) min")
    }
}

struct SpectateSetupView: View {
    @Environment(AppModel.self) private var app
    @State private var seed: UInt64 = SpectateSetup.initialSeed()
    @State private var prefs = SpectatePreferences()
    @State private var picks: [SpectatePick] = []
    @State private var didLoadPreference = false
    @State private var showsSettings = false
    @State private var showsRoster = false
    @State private var editingSeed = false
    @State private var seedText = ""

    private var options: SpectateMatchOptions {
        SpectateSetup.matchOptions(prefs, preferred: app.profile.preferredDifficulty, picks: picks)
    }

    var body: some View {
        let options = self.options
        let config = SpectateSetup.config(options: options, seed: seed, master: app.master)
        ScreenScaffold(title: L("観戦", "Spectate")) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    SpectateTeamPanel(team: .blue, roster: SpectateSetup.roster(config, team: .blue),
                                      difficulty: difficultyBinding(.blue), pinned: pinnedPositions(.blue))
                    mapColumn
                    SpectateTeamPanel(team: .red, roster: SpectateSetup.roster(config, team: .red),
                                      difficulty: difficultyBinding(.red), pinned: pinnedPositions(.red))
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
            prefs = app.profile.spectatePreferences
        }
        .onChange(of: prefs) { _, new in
            // 選択を覚えておく（次に開いた時に復元。B15）
            guard didLoadPreference, app.profile.spectatePreferences != new else { return }
            app.profile.spectatePreferences = new
        }
        .sheet(isPresented: $showsSettings) {
            SpectateSettingsSheet(prefs: $prefs).environment(app)
        }
        .sheet(isPresented: $showsRoster) {
            SpectateRosterSheet(picks: $picks, options: options, seed: seed).environment(app)
        }
        .alert(L("シードを入力", "Enter Seed"), isPresented: $editingSeed) {
            TextField("#0012ABCD", text: $seedText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("spectate_seed_field")
            Button(L("決定", "OK")) { commitSeed() }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("同じシード・同じ設定なら同じ試合になります（16 進は # 付き、10 進は数字のみ）。",
                   "The same seed and settings replay the same match (# for hex, digits for decimal)."))
        }
    }

    private func difficultyBinding(_ team: Team) -> Binding<Difficulty> {
        Binding(
            get: { options.difficulty(for: team) },
            set: { d in
                if team == .blue { prefs.blueDifficulty = d } else { prefs.redDifficulty = d }
            })
    }

    private func pinnedPositions(_ team: Team) -> Set<LanePosition> {
        Set(picks.filter { $0.team == team }.map(\.position))
    }

    /// 中央: VS とマップの選択。
    private var mapColumn: some View {
        VStack(spacing: 6) {
            Text("VS")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Theme.gold, .white], startPoint: .top, endPoint: .bottom))
                .fixedSize()
                .accessibilityHidden(true)
            Text(L("マップ", "Map"))
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
            LiveOpsSegmented(options: SpectateMap.allCases.map {
                LiveOpsSegmentOption(value: $0, title: SpectateSetup.mapTitle($0),
                                     symbol: $0 == .brawl ? "burst.fill" : "map.fill",
                                     identifier: "spectate_map_\($0 == .brawl ? "brawl" : "standard")")
            }, selection: $prefs.map, axis: .vertical, onChange: { _ in
                app.audio.play(.uiTap)
                // マップが変わると枠のポジション適性も変わるので、指定はそのまま（ドラフトがやり直される）
            })
            .accessibilityHint(SpectateSetup.mapDetail(prefs.map))
        }
        .frame(width: 92)
    }

    private func controlBar(_ config: MatchConfig) -> some View {
        Panel(padding: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(SpectateSetup.seedLabel(seed))
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("spectate_seed")
                    Text(L("シード", "Seed"))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("シード \(SpectateSetup.seedLabel(seed))", "Seed \(SpectateSetup.seedLabel(seed))"))
                LiveOpsIconButton(symbol: "doc.on.doc", label: L("シードをコピー", "Copy seed"), tint: Theme.textPrimary,
                                  identifier: "spectate_seed_copy") {
                    UIPasteboard.general.string = SpectateSetup.seedLabel(seed)
                    app.haptics.tap()
                    app.showToast(L("シードをコピーしました", "Seed copied"))
                }
                LiveOpsIconButton(symbol: "number", label: L("シードを入力", "Enter seed"), tint: Theme.textPrimary,
                                  identifier: "spectate_seed_edit") {
                    seedText = SpectateSetup.seedLabel(seed)
                    editingSeed = true
                }
                LiveOpsIconButton(symbol: "dice.fill", label: L("編成を再抽選", "Reroll teams"), tint: Theme.cyan,
                                  identifier: "spectate_reroll") {
                    app.audio.play(.uiTap)
                    app.haptics.tap()
                    seed = SpectateSetup.newSeed()
                }
                Divider().frame(height: 30).overlay(Theme.panelStroke)
                LiveOpsIconButton(symbol: picks.isEmpty ? "person.2" : "person.2.fill",
                                  label: L("ヒーローを指定", "Pick heroes") + (picks.isEmpty ? "" : L("（\(picks.count) 枠指定中）", " (\(picks.count) set)")),
                                  tint: picks.isEmpty ? Theme.textPrimary : Theme.gold, identifier: "spectate_roster") {
                    FlowFX.tap(app)
                    showsRoster = true
                }
                LiveOpsIconButton(symbol: "slider.horizontal.3", label: L("観戦の設定と記録", "Spectate settings & records"),
                                  identifier: "spectate_settings") {
                    FlowFX.tap(app)
                    showsSettings = true
                }
                Spacer(minLength: 2)
                ViewThatFits(in: .horizontal) {
                    settingsSummary
                    Color.clear.frame(width: 0, height: 0)
                }
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

    /// 速度・視界・最大時間の要約（幅に余裕がある時だけ）と「報酬なし」の注記。
    private var settingsSummary: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(SpectateSetup.speedTitle(prefs.speed)) · \(SpectateSetup.visionTitle(prefs.vision)) · \(SpectateSetup.durationTitle(prefs.maxMinutes))")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
            Text(L("報酬・戦績なし", "No rewards"))
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func commitSeed() {
        guard let parsed = SpectateSetup.parseSeed(seedText) else {
            FlowFX.error(app)
            app.showToast(L("シードを読み取れませんでした", "Couldn't read the seed"))
            return
        }
        seed = parsed
        app.haptics.tap()
    }

    private func start(_ config: MatchConfig) {
        app.audio.play(.uiConfirm)
        app.startBattle(SpectateSetup.launch(config: config, prefs: prefs))
    }
}

private struct SpectateTeamPanel: View {
    let team: Team
    let roster: [PlayerSlot]
    @Binding var difficulty: Difficulty
    let pinned: Set<LanePosition>
    @Environment(AppModel.self) private var app

    var body: some View {
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: LiveOpsFormat.teamSymbol(team)).font(.system(size: 11, weight: .bold))
                Text(LiveOpsFormat.teamName(team)).font(Theme.heading(14)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                difficultyMenu(color: color)
            }
            .foregroundStyle(color)
            // 5 人を縦に等分配置（最小の SE でもスクロールなしで収まる）
            VStack(spacing: 3) {
                ForEach(roster, id: \.position) { slot in
                    row(slot, color: color)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

    /// チームの AI 難易度（44pt のメニュー）。
    private func difficultyMenu(color: Color) -> some View {
        let teamKey = team == .blue ? "blue" : "red"
        return Menu {
            ForEach(Difficulty.allCases, id: \.self) { d in
                Button {
                    difficulty = d
                    app.audio.play(.uiTap)
                } label: {
                    if d == difficulty {
                        Label(LiveOpsFormat.difficultyName(d), systemImage: "checkmark")
                    } else {
                        Text(LiveOpsFormat.difficultyName(d))
                    }
                }
                .accessibilityIdentifier("spectate_difficulty_\(teamKey)_\(d.rawValue)")
            }
        } label: {
            HStack(spacing: 4) {
                Text("AI")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text(LiveOpsFormat.difficultyName(difficulty))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(L("\(LiveOpsFormat.teamName(team))の AI 難易度、\(LiveOpsFormat.difficultyName(difficulty))",
                              "\(LiveOpsFormat.teamName(team)) AI level, \(LiveOpsFormat.difficultyName(difficulty))"))
        .accessibilityHint(LiveOpsFormat.difficultyDetail(difficulty))
        .accessibilityIdentifier("spectate_difficulty_\(teamKey)")
    }

    private func row(_ slot: PlayerSlot, color: Color) -> some View {
        let def = app.master.hero(slot.heroID)
        let isPinned = pinned.contains(slot.position)
        return HStack(spacing: 8) {
            HeroPortraitView(heroID: slot.heroID, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(def.map { MasterText.hero($0) } ?? slot.heroID)
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(def.map { MasterText.role($0.role) } ?? "")
                    .font(Theme.body(10))
                    .foregroundStyle(def.map { Theme.roleColor($0.role) } ?? Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .accessibilityLabel(L("指定", "Picked"))
            }
            Text(LiveOpsFormat.positionName(slot.position))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 設定と記録

/// 観戦の設定（速度・視界・自動カメラ・最大時間）と観戦の記録（通算・今週の目標・実績）。
private struct SpectateSettingsSheet: View {
    @Binding var prefs: SpectatePreferences
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 10) {
                HStack {
                    Text(L("観戦の設定", "Spectate Settings"))
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    FlowCloseButton(identifier: "spectate_settings_close") { dismiss() }
                }
                HStack(alignment: .top, spacing: 12) {
                    ScrollView { settings.padding(.bottom, 8) }
                        .frame(maxWidth: .infinity)
                    ScrollView { SpectateWatchRecordPanel().padding(.bottom, 8) }
                        .frame(width: 260)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeled(L("再生速度", "Speed")) {
                LiveOpsSegmented(options: BattleController.spectatorSpeeds.map {
                    LiveOpsSegmentOption(value: $0, title: SpectateSetup.speedTitle($0),
                                         identifier: "spectate_pref_speed_\(SpectateSetup.speedTitle($0).dropLast())")
                }, selection: $prefs.speed, onChange: { _ in app.audio.play(.uiTap) })
            }
            labeled(L("視界", "Vision")) {
                LiveOpsSegmented(options: [nil, Team.blue, Team.red].map { v in
                    LiveOpsSegmentOption(value: v, title: SpectateSetup.visionTitle(v),
                                         symbol: v.map { LiveOpsFormat.teamSymbol($0) } ?? "eye.fill",
                                         identifier: "spectate_pref_vision_\(v.map { $0 == .blue ? "blue" : "red" } ?? "all")")
                }, selection: $prefs.vision, onChange: { _ in app.audio.play(.uiTap) })
                Text(L("全体: 霧なしで両チームが見えます。チーム視点: そのチームの霧で見ます（観戦中も切り替え可）。",
                       "Full: no fog, both teams visible. Team view: that team's fog (switchable while watching)."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $prefs.director) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("自動カメラ", "Auto Camera")).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary)
                    Text(L("集団戦や目標の取り合いへカメラが自動で向きます。", "The camera follows fights and objectives automatically."))
                        .font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                }
            }
            .toggleStyle(LiveOpsToggleStyle())
            .accessibilityIdentifier("spectate_pref_director")
            labeled(L("最大試合時間", "Max Duration")) {
                LiveOpsSegmented(options: SpectateSetup.maxMinutesChoices.map {
                    LiveOpsSegmentOption(value: $0, title: SpectateSetup.durationTitle($0), identifier: "spectate_pref_duration_\($0)")
                }, selection: $prefs.maxMinutes, onChange: { _ in app.audio.play(.uiTap) })
                Text(L("時間切れはタワー・キルの多いチームの勝ち（既定: 標準 40 分・乱闘 15 分）。",
                       "At the limit, the team with more towers/kills wins (default: Standard 40 min, Brawl 15 min)."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
            content()
        }
    }
}

/// 観戦の記録（通算の観戦数・リプレイ・観戦時間、今週の観戦目標、観戦の実績）。報酬は無い。
struct SpectateWatchRecordPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.profile
        let goals = LiveOpsService.watchGoalProgress(profile: p, now: Date())
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                LiveOpsSectionHeader(title: L("観戦の記録", "Watch Record"), symbol: "eye.fill", tint: Theme.cyan)
                HStack(spacing: 6) {
                    stat(L("観戦", "Matches"), "\(p.career.spectatedMatches)")
                    stat(L("リプレイ", "Replays"), "\(p.career.replaysWatched)")
                    stat(L("時間", "Time"), hours(p.career.watchedSeconds))
                }
                Text(L("今週の観戦目標", "This Week"))
                    .font(Theme.heading(12))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(goals) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.goal.title).font(Theme.body(11)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 2)
                            Text("\(entry.progress)/\(entry.goal.target)")
                                .font(Theme.mono(11))
                                .foregroundStyle(entry.progress >= entry.goal.target ? Theme.success : Theme.textSecondary)
                        }
                        LiveOpsProgressBar(fraction: Double(entry.progress) / Double(max(1, entry.goal.target)),
                                           tint: entry.progress >= entry.goal.target ? Theme.success : Theme.cyan, height: 5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.goal.title) \(entry.progress) / \(entry.goal.target)")
                }
                Text(L("実績", "Achievements"))
                    .font(Theme.heading(12))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(LiveOpsService.watchAchievements) { def in
                    let value = LiveOpsService.achievementValue(id: def.id, profile: p, master: app.master)
                    let done = p.achievements[def.id]?.unlockedAt != nil || value >= def.target
                    HStack(spacing: 6) {
                        Image(systemName: done ? "trophy.fill" : "trophy")
                            .foregroundStyle(done ? Theme.gold : Theme.textSecondary)
                        Text(def.title).font(Theme.body(11)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        Text("\(Int(value))/\(Int(def.target))").font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(L("最後まで見た試合・リプレイを 1 件につき 1 回数えます。観戦では報酬・戦績は増えません。",
                       "Each match or replay counts once when watched to the end. Watching grants no rewards or records."))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("spectate_watch_record")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textPrimary).monospacedDigit()
            Text(title).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private func hours(_ seconds: Double) -> String {
        let minutes = Int((seconds.isFinite ? max(0, seconds) : 0) / 60)
        return minutes >= 60 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : L("\(minutes) 分", "\(minutes)m")
    }
}

// MARK: - ヒーローの指定

/// 枠ごとのヒーロー指定（指定の無い枠は AI がドラフト）。
private struct SpectateRosterSheet: View {
    @Binding var picks: [SpectatePick]
    let options: SpectateMatchOptions
    let seed: UInt64
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeam: Team = .blue
    @State private var selectedPosition: LanePosition = .top
    @State private var roleFilter: Role?

    var body: some View {
        var current = options
        current.picks = picks
        let config = SpectateSetup.config(options: current, seed: seed, master: app.master)
        return ZStack {
            StarfieldBackground()
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(L("ヒーローの指定", "Pick Heroes"))
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("指定の無い枠は AI が選びます", "Unpicked slots are drafted by the AI"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Button {
                        FlowFX.tap(app)
                        picks.removeAll()
                    } label: {
                        Label(L("すべて AI", "All AI"), systemImage: "arrow.uturn.backward").lineLimit(1)
                    }
                    .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                    .disabled(picks.isEmpty)
                    .accessibilityIdentifier("spectate_roster_clear")
                    FlowCloseButton(identifier: "spectate_roster_close") { dismiss() }
                }
                HStack(alignment: .top, spacing: 10) {
                    HStack(alignment: .top, spacing: 6) {
                        slotColumn(.blue, config: config)
                        slotColumn(.red, config: config)
                    }
                    .frame(width: 330)
                    heroGrid(config: config)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .preferredColorScheme(.dark)
    }

    private func pick(_ team: Team, _ pos: LanePosition) -> SpectatePick? {
        picks.first { $0.team == team && $0.position == pos }
    }

    private func slotColumn(_ team: Team, config: MatchConfig) -> some View {
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: LiveOpsFormat.teamSymbol(team))
                Text(LiveOpsFormat.teamName(team)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(Theme.heading(12))
            .foregroundStyle(color)
            ForEach(SpectateSetup.roster(config, team: team), id: \.position) { slot in
                slotButton(slot, color: color)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func slotButton(_ slot: PlayerSlot, color: Color) -> some View {
        let selected = slot.team == selectedTeam && slot.position == selectedPosition
        let pinned = pick(slot.team, slot.position) != nil
        let name = app.master.hero(slot.heroID).map { MasterText.hero($0) } ?? slot.heroID
        return Button {
            app.audio.play(.uiTap)
            selectedTeam = slot.team
            selectedPosition = slot.position
        } label: {
            HStack(spacing: 6) {
                HeroPortraitView(heroID: slot.heroID, size: 30)
                    .opacity(pinned ? 1 : 0.65)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Theme.heading(12)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    Text(pinned ? L("指定", "Picked") : L("AI", "AI"))
                        .font(Theme.body(10))
                        .foregroundStyle(pinned ? Theme.gold : Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Text(LiveOpsFormat.positionName(slot.position))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? color.opacity(0.28) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Theme.gold : Theme.panelStroke, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LiveOpsFormat.teamName(slot.team)) \(LiveOpsFormat.positionName(slot.position))、\(name)、"
                            + (pinned ? L("指定", "picked") : L("AI が選択", "AI draft")))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("spectate_slot_\(slot.team == .blue ? "blue" : "red")_\(slot.position.rawValue)")
    }

    private func heroGrid(config: MatchConfig) -> some View {
        let heroes = app.master.heroes.filter { roleFilter == nil || $0.role == roleFilter }
        let current = pick(selectedTeam, selectedPosition)
        return Panel(padding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            FlowFX.tap(app)
                            picks.removeAll { $0.team == selectedTeam && $0.position == selectedPosition }
                        } label: {
                            Label(L("AI に任せる", "Let AI pick"), systemImage: "cpu")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(current == nil ? Color.black.opacity(0.85) : Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(current == nil ? AnyShapeStyle(Theme.cyan) : AnyShapeStyle(Color.white.opacity(0.08))))
                                .overlay(Capsule().stroke(Theme.panelStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("spectate_slot_auto")
                        roleChip(nil)
                        ForEach(Role.allCases, id: \.self) { roleChip($0) }
                    }
                }
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 76), spacing: 6)], spacing: 6) {
                        ForEach(heroes) { hero in
                            heroCell(hero, current: current)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func roleChip(_ role: Role?) -> some View {
        let isSel = roleFilter == role
        return Button {
            app.audio.play(.uiTap)
            roleFilter = role
        } label: {
            HStack(spacing: 4) {
                if let role { Image(systemName: Theme.roleSymbol(role)) }
                Text(role.map { MasterText.role($0) } ?? L("全ロール", "All")).lineLimit(1)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isSel ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSel ? AnyShapeStyle(role.map { Theme.roleColor($0) } ?? Theme.gold)
                                            : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(isSel ? Color.white.opacity(0.5) : Theme.panelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSel ? .isSelected : [])
        .accessibilityIdentifier("spectate_role_\(role?.rawValue ?? "all")")
    }

    private func heroCell(_ hero: HeroDef, current: SpectatePick?) -> some View {
        let selected = current?.heroID == hero.heroID
        // 他の枠で指定済みのヒーローは選べない（同じヒーローは 1 人まで）
        let takenElsewhere = picks.contains { $0.heroID == hero.heroID && !($0.team == selectedTeam && $0.position == selectedPosition) }
        return Button {
            app.audio.play(.uiTap)
            app.haptics.tap()
            picks.removeAll { $0.team == selectedTeam && $0.position == selectedPosition }
            picks.append(SpectatePick(team: selectedTeam, position: selectedPosition, heroID: hero.heroID))
        } label: {
            VStack(spacing: 3) {
                HeroPortraitView(heroID: hero.heroID, size: 50)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Theme.gold : .clear, lineWidth: 3))
                Text(MasterText.hero(hero))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .opacity(takenElsewhere ? 0.3 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(takenElsewhere)
        .accessibilityLabel("\(MasterText.hero(hero)), \(MasterText.role(hero.role))" + (takenElsewhere ? L("、指定済み", ", already picked") : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("spectate_hero_\(hero.heroID)")
    }
}
