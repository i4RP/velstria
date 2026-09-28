import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI015 プロフィール / UI016 戦績 / UI017 実績。

// MARK: - UI015 プロフィール

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var editingName = false

    var body: some View {
        ScreenScaffold(title: L("プロフィール", "Profile")) {
            HStack(alignment: .top, spacing: 14) {
                identityPanel
                    .frame(width: 244)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        avatarPicker
                        careerSection
                        topHeroes
                        links
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .overlay {
            if editingName {
                NameEditOverlay(initial: app.profile.displayName) { newName in
                    if let newName {
                        app.profile.displayName = newName
                        FlowFX.confirm(app)
                        app.showToast(L("名前を変更しました", "Name updated"))
                    }
                    withAnimation(.spring(duration: 0.3)) { editingName = false }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: 左: 本人情報

    private var identityPanel: some View {
        let p = app.profile
        return ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    StarRingView(speed: 0.06, starCount: 20, showsCore: false)
                        .frame(width: 220, height: 70)
                        .offset(y: 34)
                    HeroPortraitView(heroID: p.avatarHeroID, size: 92, showsRole: false)
                        .glowPulse(Theme.gold, radius: 14)
                }
                .frame(height: 112)
                HStack(spacing: 6) {
                    Text(p.displayName.isEmpty ? L("プレイヤー", "Player") : p.displayName)
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Button {
                        FlowFX.tap(app)
                        withAnimation(.spring(duration: 0.3)) { editingName = true }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.gold)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("名前を変更", "Edit name"))
                    .accessibilityIdentifier("profile_edit_name")
                }
                VStack(spacing: 4) {
                    AccountLevelBar(level: p.accountLevel, xp: p.accountXP, width: 130)
                    Text("XP \(p.accountXP) / \(FlowAccountXP.required(forLevel: p.accountLevel))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                }
                Button {
                    FlowFX.tap(app)
                    app.router.push(.rankOverview)
                } label: {
                    RankInlineView(rank: p.rank, emblemSize: 26, font: Theme.heading(13))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .glass(cornerRadius: 12, tint: FlowText.tierColors(p.rank.tier)[0])
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile_rank")
                VStack(alignment: .leading, spacing: 4) {
                    infoRow("person.text.rectangle", "ID", shortID(p.playerID))
                    infoRow("calendar", L("開始日", "Since"), FlowText.date(p.createdAt, time: false))
                    infoRow("sun.max", L("ログイン日数", "Login days"), "\(p.totalLoginDays)")
                    infoRow("person.3", L("所持ヒーロー", "Heroes owned"), "\(p.ownedHeroIDs.count) / \(app.master.heroes.count)")
                }
                .padding(10)
                .glass(cornerRadius: 12)
            }
            .padding(.vertical, 4)
        }
    }

    private func shortID(_ id: String) -> String {
        let hex = id.replacingOccurrences(of: "-", with: "").uppercased()
        return String(hex.prefix(4)) + "-" + String(hex.dropFirst(4).prefix(4))
    }

    private func infoRow(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.cyan).frame(width: 16)
            Text(title).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 右: アイコン選択

    private var avatarPicker: some View {
        let owned = app.master.heroes.filter { app.owns(heroID: $0.heroID) }
        return VStack(alignment: .leading, spacing: 8) {
            FlowSectionTitle(title: L("アイコン", "Avatar"), symbol: "person.crop.square",
                             trailing: L("所持ヒーローから選択", "Choose from your heroes"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(owned) { h in
                        Button {
                            FlowFX.tap(app)
                            app.profile.avatarHeroID = h.heroID
                        } label: {
                            HeroGridCell(hero: h, selected: app.profile.avatarHeroID == h.heroID, size: 50)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile_avatar_\(h.heroID)")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: 通算成績

    private var careerSection: some View {
        let c = app.profile.career
        let winRate = c.matches > 0 ? Double(c.wins) / Double(c.matches) : 0
        let kda = Double(c.kills + c.assists) / Double(max(1, c.deaths))
        return VStack(alignment: .leading, spacing: 8) {
            FlowSectionTitle(title: L("通算成績", "Career"), symbol: "chart.bar.fill")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                FlowStatCell(title: L("試合", "Matches"), value: "\(c.matches)")
                FlowStatCell(title: L("勝率", "Win rate"), value: c.matches > 0 ? "\(Int((winRate * 100).rounded()))%" : "—",
                             tint: winRate >= 0.5 ? Theme.success : Theme.textPrimary)
                FlowStatCell(title: "KDA", value: c.matches > 0 ? String(format: "%.2f", kda) : "—", tint: Theme.cyan)
                FlowStatCell(title: "MVP", value: "\(c.mvps)", tint: Theme.gold)
                FlowStatCell(title: L("最長連勝", "Best streak"), value: "\(c.longestWinStreak)")
                FlowStatCell(title: L("現在の連勝", "Current streak"), value: "\(c.currentWinStreak)")
                FlowStatCell(title: L("ペンタキル", "Penta kills"), value: "\(c.pentaKills)")
                FlowStatCell(title: L("総ダメージ", "Total damage"), value: FlowText.compactNumber(c.totalDamage))
            }
        }
    }

    private var topHeroes: some View {
        let per = app.profile.career.perHero
        let top = per.keys.sorted { a, b in
            let ma = per[a]?.matches ?? 0, mb = per[b]?.matches ?? 0
            return ma == mb ? a < b : ma > mb
        }
        .prefix(3)
        return VStack(alignment: .leading, spacing: 8) {
            FlowSectionTitle(title: L("よく使うヒーロー", "Most Played"), symbol: "flame.fill")
            if top.isEmpty {
                Text(L("まだ試合の記録がありません。対戦してみましょう！", "No matches yet — jump into a battle!"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(cornerRadius: 12)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(top), id: \.self) { id in
                        let hc = per[id] ?? HeroCareer()
                        HStack(spacing: 8) {
                            HeroPortraitView(heroID: id, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.master.hero(id).map { MasterText.hero($0) } ?? id)
                                    .font(Theme.heading(12))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(L("\(hc.matches) 試合 · 勝率 \(hc.matches > 0 ? hc.wins * 100 / hc.matches : 0)%",
                                       "\(hc.matches) games · \(hc.matches > 0 ? hc.wins * 100 / hc.matches : 0)% WR"))
                                    .font(Theme.body(10))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .glass(cornerRadius: 12)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var links: some View {
        HStack(spacing: 8) {
            linkButton("list.bullet.rectangle.fill", L("戦績", "Records"), .records, "profile_records")
            linkButton("trophy.fill", L("実績", "Achievements"), .achievements, "profile_achievements",
                       badge: HomeBadges.claimableAchievements(app.profile))
            linkButton("list.number", L("ランキング", "Ladder"), .ranking, "profile_ranking")
            linkButton("externaldrive.fill.badge.person.crop", L("データ連携", "Account & Data"), .accountLink, "profile_accountLink")
        }
    }

    private func linkButton(_ symbol: String, _ title: String, _ route: Route, _ id: String, badge: Int = 0) -> some View {
        Button {
            FlowFX.tap(app)
            app.router.push(route)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.cyan)
                Text(title).font(Theme.heading(11)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .glass(cornerRadius: 12)
            .overlay(alignment: .topTrailing) { FlowCountBadge(count: badge).offset(x: 3, y: -3) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// 名前変更のオーバーレイ（ソフトウェアキーボードに隠れないよう上寄せ）。
private struct NameEditOverlay: View {
    let initial: String
    /// nil = キャンセル。
    let onDone: (String?) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private var issue: PlayerNameRules.Issue? { PlayerNameRules.validate(name) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { onDone(nil) }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("プレイヤー名の変更", "Change Player Name"))
                    .font(Theme.heading(17))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    TextField(L("プレイヤー名", "Player name"), text: $name)
                        .font(Theme.heading(17))
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { if issue == nil { onDone(PlayerNameRules.normalized(name)) } }
                        .accessibilityIdentifier("profile_name_field")
                    Text("\(PlayerNameRules.normalized(name).count)/\(PlayerNameRules.maxLength)")
                        .font(Theme.mono(12))
                        .foregroundStyle(issue == .tooLong ? Theme.danger : Theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .glass(cornerRadius: 12, tint: Theme.cyan, highlighted: true)
                if let issue {
                    Text(PlayerNameRules.message(issue)).font(Theme.body(12)).foregroundStyle(Theme.danger)
                }
                HStack {
                    Spacer()
                    Button(L("キャンセル", "Cancel")) { onDone(nil) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("profile_name_cancel")
                    Button(L("保存", "Save")) { onDone(PlayerNameRules.normalized(name)) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(issue != nil)
                        .opacity(issue == nil ? 1 : 0.5)
                        .accessibilityIdentifier("profile_name_save")
                }
            }
            .padding(18)
            .frame(maxWidth: 460)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelStroke))
            .padding(.top, 16)
        }
        .onAppear {
            name = initial
            focused = true
        }
    }
}

// MARK: - UI016 戦績

struct RecordsView: View {
    private enum Filter: Hashable { case all, standard, ranked, other }

    @Environment(AppModel.self) private var app
    @State private var filter: Filter = .all
    @State private var selected: MatchRecord?
    @State private var pendingLaunch: BattleLaunch?

    private var records: [MatchRecord] {
        app.profile.matchHistory
            .filter { r in
                switch filter {
                case .all: return true
                case .standard: return r.mode == .standard
                case .ranked: return r.mode == .ranked
                case .other: return r.mode != .standard && r.mode != .ranked
                }
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScreenScaffold(title: L("戦績", "Match History")) {
            let list = records
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    summaryStrip(list)
                    FlowTabBar(items: [
                        .init(tab: Filter.all, title: L("すべて", "All"), symbol: "square.grid.2x2", identifier: "records_filter_all"),
                        .init(tab: Filter.standard, title: L("通常", "Standard"), symbol: "person.3.fill", identifier: "records_filter_standard"),
                        .init(tab: Filter.ranked, title: L("ランク", "Ranked"), symbol: "crown.fill", identifier: "records_filter_ranked"),
                    ], selection: $filter)
                }
                if list.isEmpty {
                    FlowEmptyState(symbol: "list.bullet.rectangle", title: L("戦績はまだありません", "No matches yet"),
                                   message: L("対戦を終えると、直近 50 試合の記録がここに残ります。", "Your 50 most recent matches will be listed here."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                                Button {
                                    FlowFX.tap(app)
                                    selected = r
                                } label: {
                                    RecordRow(record: r, hasReplay: replayMeta(for: r) != nil)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("records_row_\(i)")
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .sheet(item: $selected, onDismiss: startPendingReplay) { r in
            RecordDetailSheet(record: r, replay: replayMeta(for: r)) { launch in
                pendingLaunch = launch
                selected = nil
            }
            .environment(app)
        }
    }

    private func replayMeta(for r: MatchRecord) -> ReplayMeta? {
        guard let id = r.replayID else { return nil }
        return app.profile.replays.first { $0.id == id }
    }

    /// シートが閉じ終わってから戦闘を開始する（表示の重なりを避ける）。
    private func startPendingReplay() {
        guard let launch = pendingLaunch else { return }
        pendingLaunch = nil
        app.startBattle(launch)
    }

    private func summaryStrip(_ list: [MatchRecord]) -> some View {
        let wins = list.filter { $0.won == true }.count
        let decided = list.filter { $0.won != nil }.count
        let k = list.reduce(0) { $0 + $1.kills }, d = list.reduce(0) { $0 + $1.deaths }, a = list.reduce(0) { $0 + $1.assists }
        let mvps = list.filter(\.isMVP).count
        return HStack(spacing: 6) {
            miniStat(L("試合", "Games"), "\(list.count)")
            miniStat(L("勝率", "Win%"), decided > 0 ? "\(wins * 100 / decided)%" : "—")
            miniStat("KDA", list.isEmpty ? "—" : String(format: "%.1f", Double(k + a) / Double(max(1, d))))
            miniStat("MVP", "\(mvps)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(Theme.mono(14)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .frame(minWidth: 52, minHeight: 44)
        .padding(.horizontal, 4)
        .glass(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordRow: View {
    let record: MatchRecord
    let hasReplay: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let r = record
        let color: Color = r.won == true ? Theme.success : (r.won == false ? Theme.danger : Theme.textSecondary)
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: r.won == true ? "crown.fill" : (r.won == false ? "xmark.shield.fill" : "minus.circle"))
                    .font(.system(size: 14, weight: .bold))
                Text(r.won == true ? L("勝利", "WIN") : (r.won == false ? L("敗北", "LOSS") : "—"))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(color)
            .frame(width: 44)
            HeroPortraitView(heroID: r.heroID, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.master.hero(r.heroID).map { MasterText.hero($0) } ?? r.heroID)
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(FlowText.mode(r.mode))" + (r.mode == .standard || r.mode == .ranked ? " · \(FlowText.difficulty(r.difficulty))" : ""))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 110, alignment: .leading)
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(FlowText.kda(r.kills, r.deaths, r.assists)).font(Theme.mono(13)).foregroundStyle(Theme.textPrimary)
                Text("CS \(r.creepScore) · \(FlowText.compactNumber(r.gold))G").font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            GradeBadge(grade: r.grade, size: 26)
            if r.isMVP { MVPBadge(compact: true) }
            VStack(alignment: .trailing, spacing: 1) {
                Text(FlowText.duration(r.duration)).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
                Text(FlowText.date(r.date)).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .frame(width: 100, alignment: .trailing)
            Image(systemName: hasReplay ? "play.rectangle.fill" : "chevron.right")
                .font(.system(size: hasReplay ? 15 : 11, weight: .bold))
                .foregroundStyle(hasReplay ? Theme.cyan : Theme.textSecondary)
                .frame(width: 20)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 58)
        .background(
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: 3)
                Spacer()
            }
        )
        .glass(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RecordDetailSheet: View {
    let record: MatchRecord
    let replay: ReplayMeta?
    let onWatch: (BattleLaunch) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(record.won == true ? L("勝利", "Victory") : (record.won == false ? L("敗北", "Defeat") : L("試合終了", "Match Ended")))
                        .font(Theme.title(22))
                        .foregroundStyle(record.won == true ? Theme.gold : (record.won == false ? Theme.danger : Theme.textPrimary))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(FlowText.mode(record.mode)) · \(FlowText.difficulty(record.difficulty)) · \(FlowText.duration(record.duration))")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                        Text(FlowText.date(record.date)).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if replay != nil {
                        Button(action: watch) {
                            Label(L("リプレイを見る", "Watch Replay"), systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                        .accessibilityIdentifier("records_watch_replay")
                    }
                    FlowCloseButton(identifier: "records_detail_close") { dismiss() }
                }
                ScrollView {
                    if let summary = record.summary {
                        MatchScoreTable(summary: summary)
                            .padding(.bottom, 10)
                    } else {
                        playerOnly
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
    }

    private var playerOnly: some View {
        let r = record
        return HStack(spacing: 12) {
            HeroPortraitView(heroID: r.heroID, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.master.hero(r.heroID).map { MasterText.hero($0) } ?? r.heroID)
                    .font(Theme.heading(16)).foregroundStyle(Theme.textPrimary)
                Text("K/D/A \(FlowText.kda(r.kills, r.deaths, r.assists)) · CS \(r.creepScore) · \(FlowText.compactNumber(r.gold)) G · \(L("ダメージ", "Damage")) \(FlowText.compactNumber(r.damageToHeroes))")
                    .font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            GradeBadge(grade: r.grade, size: 34)
            if r.isMVP { MVPBadge() }
        }
        .padding(14)
        .glass(cornerRadius: 14)
    }

    private func watch() {
        guard let meta = replay, let data = app.persistence.loadReplay(meta) else {
            FlowFX.error(app)
            app.showToast(L("リプレイを読み込めませんでした", "Couldn't load the replay"))
            return
        }
        guard data.config.simVersion == MatchConfig.currentSimVersion else {
            FlowFX.error(app)
            app.showToast(L("古いバージョンのリプレイは再生できません", "This replay is from an older version and can't be played"))
            return
        }
        FlowFX.confirm(app)
        onWatch(BattleLaunch(config: data.config, replay: data))
    }
}

// MARK: - UI017 実績

struct AchievementsView: View {
    private enum Filter: Hashable { case all, unlocked, inProgress }

    @Environment(AppModel.self) private var app
    @State private var filter: Filter = .all

    private func progress(_ def: AchievementDef) -> AchievementProgress {
        app.profile.achievements[def.id] ?? AchievementProgress()
    }

    private func isUnlocked(_ def: AchievementDef) -> Bool {
        let p = progress(def)
        return p.unlockedAt != nil || p.progress >= def.target
    }

    var body: some View {
        ScreenScaffold(title: L("実績", "Achievements")) {
            let defs = LiveOpsService.achievements
            if defs.isEmpty {
                FlowEmptyState(symbol: "trophy", title: L("実績はまだありません", "No achievements yet"),
                               message: L("対戦や育成で条件を満たすと実績が解除されます。", "Play matches to unlock achievements."))
            } else {
                let unlocked = defs.filter { isUnlocked($0) }.count
                let list = defs.filter { d in
                    switch filter {
                    case .all: return true
                    case .unlocked: return isUnlocked(d)
                    case .inProgress: return !isUnlocked(d)
                    }
                }
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                            Text("\(unlocked) / \(defs.count)").font(Theme.mono(15)).foregroundStyle(Theme.textPrimary)
                            FlowProgressBar(value: Double(unlocked) / Double(max(1, defs.count)), tint: Theme.gold, height: 6)
                                .frame(width: 120)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(L("達成 \(unlocked) / \(defs.count)", "\(unlocked) of \(defs.count) unlocked"))
                        Spacer()
                        FlowTabBar(items: [
                            .init(tab: Filter.all, title: L("すべて", "All"), symbol: "square.grid.2x2", identifier: "achv_filter_all"),
                            .init(tab: Filter.unlocked, title: L("達成", "Unlocked"), symbol: "checkmark.seal.fill", identifier: "achv_filter_unlocked"),
                            .init(tab: Filter.inProgress, title: L("挑戦中", "In progress"), symbol: "hourglass", identifier: "achv_filter_progress"),
                        ], selection: $filter)
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(list) { def in
                                achievementCard(def)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func achievementCard(_ def: AchievementDef) -> some View {
        let p = progress(def)
        let unlocked = isUnlocked(def)
        let ratio = def.target > 0 ? min(1, p.progress / def.target) : (unlocked ? 1 : 0)
        return HStack(spacing: 12) {
            Image(systemName: unlocked ? "trophy.fill" : "trophy")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                .frame(width: 46, height: 46)
                .background(HexagonShape().fill(unlocked ? Theme.gold.opacity(0.18) : Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(L(def.titleJa, def.titleEn))
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(L(def.detailJa, def.detailEn))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    FlowProgressBar(value: ratio, tint: unlocked ? Theme.gold : Theme.cyan, height: 5)
                    Text("\(formatValue(min(p.progress, def.target)))/\(formatValue(def.target))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            VStack(spacing: 4) {
                if def.rewardGems > 0 {
                    AttachmentChip(attachment: MailAttachment(kind: .gem, amount: def.rewardGems), claimed: p.claimed)
                }
                if p.claimed {
                    Label(L("受取済み", "Claimed"), systemImage: "checkmark")
                        .font(Theme.body(11)).foregroundStyle(Theme.success)
                        .frame(minHeight: 32)
                } else if unlocked {
                    Button(L("受け取る", "Claim")) { claim(def) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("achv_claim_\(def.id)")
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.textSecondary).frame(minHeight: 32)
                }
            }
            .frame(width: 104)
        }
        .padding(10)
        .glass(cornerRadius: 14, tint: unlocked ? Theme.gold : Theme.panelStroke, highlighted: unlocked && !p.claimed)
        .accessibilityElement(children: .contain)
    }

    private func formatValue(_ v: Double) -> String {
        v >= 10_000 ? FlowText.compactNumber(v) : (v.rounded() == v ? "\(Int(v))" : String(format: "%.1f", v))
    }

    private func claim(_ def: AchievementDef) {
        var p = app.profile
        if let gems = LiveOpsService.claimAchievement(id: def.id, profile: &p, now: Date()) {
            app.profile = p
            FlowFX.reward(app)
            app.showToast(L("\(gems) ジェムを受け取りました", "Received \(gems) Gems"))
        } else {
            FlowFX.error(app)
            app.showToast(L("まだ受け取れません", "Not available yet"))
        }
    }
}
