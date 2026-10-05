import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI021〜025 対戦前フロー（全画面）。
// 1. モード選択 → 2a. ヒーロー選択（通常戦） / 2b. BAN・ピックのドラフト（ランク戦） → 3. 出撃準備（両チーム確認）→ 戦闘。

/// 対戦フローの状態（画面間で共有）。
@Observable
@MainActor
final class MatchFlowModel {
    enum Kind: Equatable { case standard, ranked, brawl }
    enum Step: Int, Equatable { case mode, heroSelect, draft, ready }

    var step: Step = .mode
    var kind: Kind = .standard
    var difficulty: Difficulty = .normal
    /// 時刻から作ったシード（ドラフトの AI・試合構成の両方に使う）。
    let seed: UInt64

    var heroID: String?
    var roleFilter: Role?
    var position: LanePosition = .mid
    var skinID: String?
    var spells: [String] = ["BS01", "BS03"]
    var runePageIndex: Int?

    var draft: DraftEngine?
    /// ドラフトでプレイヤーが仮選択しているヒーロー。
    var draftHover: String?
    /// AI 手番で決めた選択（演出中に画面が作り直されても同じ選択を使い、乱数を二重に進めない）。
    var aiPending: (turnIndex: Int, heroID: String?)?
    /// 出撃準備で表示・起動する構成。
    var config: MatchConfig?

    var spellPickerSlot: Int?
    var unlockCandidate: HeroDef?
    var configured = false

    init(seed: UInt64) {
        self.seed = seed
    }

    static func timeSeed(_ now: Date = Date()) -> UInt64 {
        var rng = SplitMix64(seed: UInt64(now.timeIntervalSince1970 * 1000))
        return rng.next()
    }

    /// フローのシード。UI テスト（-uiTesting）に限り `-flowSeed <n>` で固定できる（ドラフトの AI 選択を再現するため）。
    static func initialSeed() -> UInt64 {
        if DebugLaunch.isUITesting, let s = DebugLaunch.value(after: "-flowSeed").flatMap({ UInt64($0) }) { return s }
        return timeSeed()
    }

    func configure(profile: Profile, master: MasterData) {
        guard !configured else { return }
        configured = true
        difficulty = profile.preferredDifficulty
        if !profile.runePages.isEmpty {
            runePageIndex = min(max(0, profile.selectedRunePage), profile.runePages.count - 1)
        }
        let last = profile.lastPickedHeroID.flatMap { profile.ownedHeroIDs.contains($0) ? $0 : nil }
        let initial = last ?? master.heroes.first { profile.ownedHeroIDs.contains($0.heroID) }?.heroID
        if let initial { selectHero(initial, profile: profile, master: master) }
    }

    /// ヒーローを選び、ロードアウトをそのヒーローの保存値で初期化する。
    func selectHero(_ id: String, profile: Profile, master: MasterData) {
        heroID = id
        let role = master.hero(id)?.role ?? .duelist
        if kind == .ranked, let pick = draft?.playerPick, pick.heroID == id {
            position = pick.position
        } else {
            position = MatchFactory.defaultPosition(for: role)
        }
        spells = Self.sanitizedSpells(profile.heroSpells[id] ?? profile.defaultSpells, master: master)
        skinID = profile.equippedSkins[id].flatMap { profile.ownedCosmeticIDs.contains($0) ? $0 : nil }
    }

    /// 2 つの異なる有効なスペルに正規化する。
    static func sanitizedSpells(_ s: [String], master: MasterData) -> [String] {
        var out: [String] = []
        for id in s where master.spell(id) != nil && !out.contains(id) && out.count < 2 { out.append(id) }
        for id in ["BS01", "BS03", "BS04"] where out.count < 2 && !out.contains(id) { out.append(id) }
        return out
    }

    /// 枠にスペルを入れる。もう一方の枠と同じなら入れ替える。
    func setSpell(_ id: String, slot: Int) {
        guard spells.count == 2, slot == 0 || slot == 1 else { return }
        if spells[1 - slot] == id {
            spells.swapAt(0, 1)
        } else {
            spells[slot] = id
        }
    }

    func setPosition(_ p: LanePosition) {
        position = p
        if kind == .ranked { draft?.setPlayerPosition(p) }
    }

    func runeIDs(profile: Profile) -> [String] {
        guard let i = runePageIndex, profile.runePages.indices.contains(i) else { return [] }
        return profile.runePages[i].runeIDs.filter { !$0.isEmpty }
    }

    func startRanked(profile: Profile) {
        kind = .ranked
        draft = DraftEngine(seed: seed, ownedHeroIDs: profile.ownedHeroIDs)
        draftHover = nil
        aiPending = nil
        config = nil
        step = .draft
    }

    func startStandard() {
        kind = .standard
        draft = nil
        config = nil
        step = .heroSelect
    }

    func startBrawl() {
        kind = .brawl
        draft = nil
        config = nil
        step = .heroSelect
    }

    /// 構成を作る（ランク戦はドラフトの結果を AI 枠に反映）。
    func buildConfig(profile: Profile, master: MasterData) -> MatchConfig? {
        guard let heroID else { return nil }
        let name = profile.displayName.isEmpty ? "Player" : profile.displayName
        if kind == .brawl {
            return MatchFactory.brawlMatch(humanHeroID: heroID, humanName: name, humanSpells: spells,
                                           humanRunes: runeIDs(profile: profile), humanSkin: skinID,
                                           humanPosition: position, allyDifficulty: .normal,
                                           enemyDifficulty: difficulty, seed: seed, master: master)
        }
        let ranked = kind == .ranked
        let diffs = ranked ? RankService.botDifficulty(for: profile.rank) : (ally: Difficulty.normal, enemy: difficulty)
        var config = MatchFactory.standardMatch(mode: ranked ? .ranked : .standard, humanHeroID: heroID, humanName: name,
                                                humanTeam: .blue, humanSpells: spells, humanRunes: runeIDs(profile: profile),
                                                humanSkin: skinID, humanPosition: position,
                                                allyDifficulty: diffs.ally, enemyDifficulty: diffs.enemy,
                                                banned: draft?.bannedHeroIDs ?? [], seed: seed, master: master)
        if ranked, let draft {
            draft.apply(to: &config, master: master)
        }
        return config
    }
}

struct MatchFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var model = MatchFlowModel(seed: MatchFlowModel.initialSeed())

    var body: some View {
        ZStack {
            StarfieldBackground()
            Group {
                switch model.step {
                case .mode: MatchModeStep(model: model)
                case .heroSelect: HeroSelectStep(model: model)
                case .draft: DraftStep(model: model)
                case .ready: ReadyStep(model: model)
                }
            }
            .id(model.step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            if let slot = model.spellPickerSlot {
                SpellPickerOverlay(model: model, slot: slot)
                    .transition(.opacity)
                    .zIndex(2)
            }
            // 全画面表示ではルートのトーストが隠れるため、ここにも重ねる
            ToastOverlay().zIndex(3)
        }
        .animation(.spring(duration: 0.45, bounce: 0.12), value: model.step)
        .animation(.easeInOut(duration: 0.2), value: model.spellPickerSlot)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            model.configure(profile: app.profile, master: app.master)
            switch MatchFlowIntent.consume() {
            case .standard(let d)?:
                model.difficulty = d
                model.startStandard()
            case .ranked?:
                model.startRanked(profile: app.profile)
            case .brawl(let d)?:
                model.difficulty = d
                model.startBrawl()
            case nil:
                break
            }
        }
    }
}

// MARK: - 共通: ヘッダ

struct MatchFlowHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let backSymbol: String
    let backID: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: backSymbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .overlay(Circle().stroke(Theme.panelStroke))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backSymbol == "xmark" ? L("閉じる", "Close") : L("戻る", "Back"))
            .accessibilityIdentifier(backID)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.title(21))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// 手順表示（1 モード → 2 ヒーロー → 3 出撃）。
struct MatchFlowSteps: View {
    let current: Int

    var body: some View {
        let titles = [L("モード", "Mode"), L("ヒーロー", "Hero"), L("出撃", "Ready")]
        HStack(spacing: 6) {
            ForEach(titles.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(i <= current ? Color.black.opacity(0.85) : Theme.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(i <= current ? Theme.gold : Color.white.opacity(0.1)))
                    Text(titles[i])
                        .font(Theme.body(11))
                        .foregroundStyle(i == current ? Theme.textPrimary : Theme.textSecondary)
                }
                if i < titles.count - 1 {
                    Rectangle().fill(i < current ? Theme.gold : Color.white.opacity(0.15)).frame(width: 14, height: 1.5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("手順 \(current + 1) / 3", "Step \(current + 1) of 3"))
    }
}

// MARK: - 1. モード選択（UI021）

private struct MatchModeStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 10) {
            MatchFlowHeader(title: L("対戦モード", "Select Mode"), subtitle: L("オフライン · 5v5 対AI", "Offline · 5v5 vs AI"),
                            backSymbol: "xmark", backID: "flow_close", onBack: close) {
                MatchFlowSteps(current: 0)
            }
            HStack(alignment: .top, spacing: 12) {
                standardCard
                rankedCard
                shortcuts
                    .frame(width: 150)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func close() {
        FlowFX.back(app)
        app.router.isMatchFlowPresented = false
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader(symbol: "person.3.fill", tint: Theme.cyan, title: L("通常戦", "Standard"), subtitle: L("5v5 対AI", "5v5 vs AI"))
            Text(L("AI の味方 4 人と協力して、AI チームのスターコアを破壊しよう。", "Team up with 4 AI allies and destroy the enemy AI team's Star Core."))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("敵 AI の強さ", "Enemy AI"))
                .font(Theme.heading(12))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                ForEach(Difficulty.allCases, id: \.self) { d in
                    let selected = model.difficulty == d
                    Button {
                        FlowFX.tap(app)
                        withAnimation(.spring(duration: 0.25)) { model.difficulty = d }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: FlowText.difficultySymbol(d)).font(.system(size: 14, weight: .bold))
                            Text(FlowText.difficulty(d))
                                .font(Theme.heading(12))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Theme.cyan) : AnyShapeStyle(Color.white.opacity(0.08))))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? Color.white.opacity(0.6) : Theme.panelStroke, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(FlowText.difficulty(d))
                    .accessibilityIdentifier("flow_difficulty_\(d.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(Self.difficultyDetail(model.difficulty))
                .font(Theme.body(11))
                .foregroundStyle(Theme.cyan)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Label(L("勝利 220 コイン · 敗北 110 コイン", "Win 220 coins · Loss 110 coins"), systemImage: "star.circle.fill")
                .font(Theme.body(11))
                .foregroundStyle(Theme.gold)
            Spacer(minLength: 0)
            Button {
                FlowFX.confirm(app)
                model.startStandard()
            } label: {
                Label(L("ヒーロー選択へ", "Choose Hero"), systemImage: "chevron.right.2").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
            .accessibilityIdentifier("flow_mode_standard")
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(cornerRadius: 18, tint: Theme.cyan.opacity(0.8))
    }

    /// 難易度ごとの AI の特徴（DESIGN §10）。
    static func difficultyDetail(_ d: Difficulty) -> String {
        switch d {
        case .easy: return L("反応 0.6 秒・命中率 控えめ。はじめての方に。", "0.6s reactions, loose aim. Great for beginners.")
        case .normal: return L("反応 0.35 秒・標準的な立ち回り。", "0.35s reactions, standard play.")
        case .hard: return L("反応 0.15 秒・高い精度で集団行動をとる。", "0.15s reactions, precise aim and group tactics.")
        }
    }

    private var rankedCard: some View {
        let r = app.profile.rank
        let diffs = RankService.botDifficulty(for: r)
        return VStack(alignment: .leading, spacing: 8) {
            cardHeader(symbol: "crown.fill", tint: Theme.gold, title: L("ランク戦", "Ranked"), subtitle: L("BAN あり · 対AI", "Bans · vs AI"))
            Text(L("BAN とピックのドラフトを経て対戦。勝敗でランクの星が増減します。", "Draft with bans and picks. Wins and losses move your rank stars."))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            RankInlineView(rank: r, emblemSize: 26, font: Theme.heading(13))
            Label(L("味方 AI \(FlowText.difficulty(diffs.ally)) · 敵 AI \(FlowText.difficulty(diffs.enemy))",
                    "Allies \(FlowText.difficulty(diffs.ally)) · Enemies \(FlowText.difficulty(diffs.enemy))"), systemImage: "cpu")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button {
                FlowFX.confirm(app)
                model.startRanked(profile: app.profile)
            } label: {
                Label(L("ドラフトへ", "Start Draft"), systemImage: "chevron.right.2").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("flow_mode_ranked")
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(cornerRadius: 18, tint: Theme.gold.opacity(0.9))
        .glowPulse(Theme.gold.opacity(0.5), radius: 10)
    }

    private func cardHeader(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(HexagonShape().fill(tint.opacity(0.18)))
                .overlay(HexagonShape().stroke(tint.opacity(0.6)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.title(22)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(Theme.body(11)).foregroundStyle(tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var shortcuts: some View {
        VStack(spacing: 8) {
            FlowSectionTitle(title: L("その他", "More"))
            shortcut("figure.run", L("練習場", "Practice"), .practiceSetup, "flow_shortcut_practice")
            shortcut("graduationcap.fill", L("チュートリアル", "Tutorial"), .tutorialMenu, "flow_shortcut_tutorial")
            shortcut("eye.fill", L("観戦", "Spectate"), .spectateSetup, "flow_shortcut_spectate")
            Spacer(minLength: 0)
        }
    }

    /// フローを閉じて該当画面へ遷移する。
    private func shortcut(_ symbol: String, _ title: String, _ route: Route, _ id: String) -> some View {
        Button {
            FlowFX.tap(app)
            app.router.isMatchFlowPresented = false
            app.router.push(route)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.cyan).frame(width: 24)
                Text(title).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50)
            .glass(cornerRadius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - 3. 出撃準備（UI023 相当。実際の構成をそのまま表示する）

private struct ReadyStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    @State private var appeared = false
    @State private var launching = false

    var body: some View {
        VStack(spacing: 8) {
            MatchFlowHeader(title: L("出撃準備", "Ready"), subtitle: subtitle, backSymbol: "chevron.left", backID: "flow_back", onBack: back) {
                MatchFlowSteps(current: 2)
            }
            if let config = model.config {
                HStack(alignment: .center, spacing: 10) {
                    TeamLineup(team: .blue, config: config, appeared: appeared)
                    centerColumn(config)
                        .frame(width: 176)
                    TeamLineup(team: .red, config: config, appeared: appeared)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .onAppear {
            if model.config == nil { model.config = model.buildConfig(profile: app.profile, master: app.master) }
            withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.1)) { appeared = true }
        }
    }

    private var subtitle: String {
        switch model.kind {
        case .ranked:
            return L("ランク戦", "Ranked") + " · " + RankService.displayName(app.profile.rank)
        case .brawl:
            return L("乱闘", "Brawl") + " · " + L("敵 AI ", "Enemy AI ") + FlowText.difficulty(model.difficulty)
        case .standard:
            return L("通常戦", "Standard") + " · " + L("敵 AI ", "Enemy AI ") + FlowText.difficulty(model.difficulty)
        }
    }

    private func back() {
        FlowFX.back(app)
        model.config = nil
        model.step = model.kind == .ranked ? .draft : .heroSelect
    }

    private func centerColumn(_ config: MatchConfig) -> some View {
        VStack(spacing: 10) {
            ZStack {
                StarRingView(speed: 0.12, starCount: 18)
                    .frame(width: 170, height: 70)
                Text("VS")
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Theme.gold.opacity(0.7), radius: 10)
                    .scaleEffect(appeared ? 1 : 2.2)
                    .opacity(appeared ? 1 : 0)
            }
            VStack(spacing: 3) {
                Text(model.kind == .brawl ? L("乱闘の回廊", "Brawl Corridor") : L("星環の戦場", "Star Ring Battlefield"))
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.kind == .brawl ? L("単レーン · 加速", "Single lane · Accelerated")
                                          : L("3 レーン · ジャングル", "3 lanes · Jungle"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                if model.kind == .ranked {
                    Label(L("結果がランクに反映", "Counts for rank"), systemImage: "crown.fill")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.gold)
                }
            }
            Button(action: launch) {
                VStack(spacing: 0) {
                    Text(L("出撃", "DEPLOY")).font(.system(size: 22, weight: .black, design: .rounded))
                    Text("START").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(2).opacity(0.6)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(PrimaryButtonStyle())
            .glowPulse(Theme.gold, radius: 14)
            .disabled(launching)
            .accessibilityLabel(L("出撃", "Deploy"))
            .accessibilityIdentifier("flow_confirm")
        }
    }

    /// ロードアウトを保存して戦闘を開始する。
    private func launch() {
        guard !launching, let config = model.config, let heroID = model.heroID else { return }
        launching = true
        var p = app.profile
        p.lastPickedHeroID = heroID
        if model.kind == .standard { p.preferredDifficulty = model.difficulty }
        p.heroSpells[heroID] = model.spells
        if let i = model.runePageIndex { p.selectedRunePage = i }
        if let skin = model.skinID {
            p.equippedSkins[heroID] = skin
        } else {
            p.equippedSkins.removeValue(forKey: heroID)
        }
        app.profile = p
        FlowFX.confirm(app)
        app.startBattle(BattleLaunch(config: config, countsForRank: model.kind == .ranked))
    }
}

/// 出撃準備の片チーム一覧。
private struct TeamLineup: View {
    let team: Team
    let config: MatchConfig
    let appeared: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        let slots = config.players.filter { $0.team == team }.sorted { $0.position.rawValue < $1.position.rawValue }
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: FlowText.teamSymbol(team)).foregroundStyle(color)
                Text(team == .blue ? L("味方チーム", "Your Team") : L("敵チーム", "Enemy Team"))
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(FlowText.team(team)).font(Theme.body(10)).foregroundStyle(color)
            }
            ForEach(Array(slots.enumerated()), id: \.offset) { i, slot in
                LineupRow(slot: slot, color: color)
                    .offset(x: appeared ? 0 : (team == .blue ? -40 : 40))
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.2).delay(Double(i) * 0.06), value: appeared)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .glass(cornerRadius: 14, tint: color.opacity(0.7))
    }
}

private struct LineupRow: View {
    let slot: PlayerSlot
    let color: Color
    @Environment(AppModel.self) private var app

    var body: some View {
        let human = slot.controller == .human
        HStack(spacing: 7) {
            HeroPortraitView(heroID: slot.heroID, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(human ? slot.displayName : (app.master.hero(slot.heroID).map { MasterText.hero($0) } ?? slot.heroID))
                        .font(Theme.heading(12))
                        .foregroundStyle(human ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if human {
                        Text(L("あなた", "YOU"))
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Theme.gold))
                    }
                }
                HStack(spacing: 3) {
                    Image(systemName: FlowText.positionSymbol(slot.position)).font(.system(size: 9))
                    Text(FlowText.position(slot.position))
                    if !human {
                        Text("· AI \(FlowText.difficulty(slot.botDifficulty))")
                    }
                }
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2)
            HStack(spacing: 2) {
                ForEach(slot.spells, id: \.self) { SpellIconView(spellID: $0, size: 18) }
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(human ? Theme.gold.opacity(0.14) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(human ? Theme.gold.opacity(0.8) : .clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
