import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI021〜025 対戦前フロー（全画面）。
// 1. モード選択 → 2a. ヒーロー選択（通常戦） / 2b. ピックのドラフト（ランク戦） → 3. 出撃準備（両チーム確認）→ 戦闘。

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
        spells = SpellLoadoutRules.effective(heroID: id, profile: profile)
        skinID = profile.equippedSkins[id].flatMap { profile.ownedCosmeticIDs.contains($0) ? $0 : nil }
    }

    /// [選べる枠, 治癒波] に正規化する（2 枠目は治癒波で固定）。
    static func sanitizedSpells(_ s: [String], master: MasterData) -> [String] {
        SpellLoadoutRules.normalized(s, master: master)
    }

    /// 選べる枠（1 枠目）にスペルを入れる。治癒波の固定枠は変更しない。
    func setSpell(_ id: String, slot: Int) {
        spells = SpellLoadoutRules.assigning(id, slot: slot, in: spells)
    }

    func setPosition(_ p: LanePosition) {
        position = p
        if kind == .ranked { draft?.setPlayerPosition(p) }
    }

    /// 試合で使うエンブレム（一括設定で付けたもの、無ければ選んだバトルプランのもの。EmblemMath.loadout）。
    func emblem(profile: Profile, master: MasterData) -> EmblemLoadout? {
        guard let heroID else { return nil }
        return EmblemMath.loadout(for: heroID, profile: profile, master: master)
    }

    func startRanked(profile: Profile) {
        kind = .ranked
        draft = DraftEngine(seed: seed)
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
                                           humanEmblem: emblem(profile: profile, master: master), humanSkin: skinID,
                                           humanPosition: position, allyDifficulty: .normal,
                                           enemyDifficulty: difficulty, humanBuildPlan: profile.heroBuildPlans[heroID],
                                           seed: seed, master: master)
        }
        let ranked = kind == .ranked
        let diffs = ranked ? RankService.botDifficulty(for: profile.rank) : (ally: Difficulty.normal, enemy: difficulty)
        var config = MatchFactory.standardMatch(mode: ranked ? .ranked : .standard, humanHeroID: heroID, humanName: name,
                                                humanTeam: .blue, humanSpells: spells, humanEmblem: emblem(profile: profile, master: master),
                                                humanSkin: skinID, humanPosition: position,
                                                allyDifficulty: diffs.ally, enemyDifficulty: diffs.enemy,
                                                humanBuildPlan: profile.heroBuildPlans[heroID],
                                                seed: seed, master: master)
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
        .onChange(of: model.step, initial: true) { old, step in
            switch step {
            case .mode: app.audio.playMusic(.menu)
            case .heroSelect: app.audio.playMusic(.lobby)
            case .draft: app.audio.playMusic(.draft)
            case .ready: break
            }
            // モードを選んで試合の相手が決まった（ヒーロー選択・ドラフトへ進んだ）時だけ
            if old == .mode, step == .heroSelect || step == .draft { app.audio.play(.matchFound) }
        }
        .onDisappear {
            // 試合へ進まずに閉じたらホームの曲へ戻す（試合へ進む時はロード画面が曲を変える）
            if app.activeBattle == nil { app.audio.playMusic(.menu) }
        }
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

/// モード選択の並び（MLBB と同じく、遊べるモードはすべてここから入る）。
enum MatchModeCategory: String, CaseIterable, Identifiable {
    case classic, ranked, brawl, arcade, vsAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return L("クラシック", "Classic")
        case .ranked: return L("ランク", "Ranked")
        case .brawl: return L("ブロウル", "Brawl")
        case .arcade: return L("アーケード", "Arcade")
        case .vsAI: return L("VS AI & カスタム", "VS AI & Custom")
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return L("5v5 · 3 レーン", "5v5 · 3 lanes")
        case .ranked: return L("ドラフト · 5v5", "Draft · 5v5")
        case .brawl: return L("5v5 · 単レーン", "5v5 · 1 lane")
        case .arcade: return L("期間限定・変則ルール", "Limited & variant rules")
        case .vsAI: return L("カスタム・練習場", "Custom & practice")
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "flag.2.crossed.fill"
        case .ranked: return "crown.fill"
        case .brawl: return "burst.fill"
        case .arcade: return "gamecontroller.fill"
        case .vsAI: return "cpu"
        }
    }

    /// カードを押すと対戦フローを進めるモードの識別子（それ以外はカードの中のボタンで各画面へ）。
    var identifier: String? {
        switch self {
        case .classic: return "flow_mode_standard"
        case .ranked: return "flow_mode_ranked"
        case .brawl: return "flow_mode_brawl"
        case .arcade, .vsAI: return nil
        }
    }

    /// カードの中のボタン（アーケードと VS AI & カスタム。押すとフローを閉じて各画面へ）。
    var destinations: [MatchModeDestination] {
        switch self {
        case .classic, .ranked, .brawl: return []
        case .arcade:
            return [MatchModeDestination(route: .rising, title: L("ライジング", "Rising"), symbol: "chart.line.uptrend.xyaxis", id: "flow_mode_rising"),
                    MatchModeDestination(route: .magicChess, title: L("オートバトラー", "Auto Battler"), symbol: "square.grid.3x3.fill", id: "flow_mode_magicChess")]
        case .vsAI:
            return [MatchModeDestination(route: .customSetup, title: L("カスタム", "Custom"), symbol: "slider.horizontal.3", id: "flow_mode_custom"),
                    MatchModeDestination(route: .practiceSetup, title: L("練習場", "Practice"), symbol: "figure.run", id: "flow_mode_practice"),
                    MatchModeDestination(route: .tutorialMenu, title: L("チュートリアル", "Tutorial"), symbol: "graduationcap.fill", id: "flow_mode_tutorial")]
        }
    }
}

/// モード選択のカードの中のボタン（id はアクセシビリティの識別子も兼ねる）。
struct MatchModeDestination: Identifiable, Equatable {
    let route: Route
    let title: String
    let symbol: String
    let id: String
}

private struct MatchModeStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 8) {
            MatchFlowHeader(title: L("対戦モード", "Select Mode"), subtitle: L("5v5 · 対AI", "5v5 · vs AI"),
                            backSymbol: "xmark", backID: "flow_close", onBack: close) {
                MatchFlowSteps(current: 0)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(MatchModeCategory.allCases) { card($0) }
            }
            .frame(maxHeight: .infinity)
            difficultyRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func close() {
        FlowFX.back(app)
        app.router.isMatchFlowPresented = false
    }

    private func modeTint(_ c: MatchModeCategory) -> Color {
        switch c {
        case .classic: return Theme.cyan
        case .ranked: return Theme.gold
        case .brawl: return Color(red: 1.0, green: 0.55, blue: 0.18)
        case .arcade: return Theme.success
        case .vsAI: return Color(red: 0.56, green: 0.70, blue: 1.0)
        }
    }

    @ViewBuilder
    private func card(_ c: MatchModeCategory) -> some View {
        if c.destinations.isEmpty {
            Button { start(c) } label: {
                cardBody(c) { cardFooter(c) }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(c.identifier ?? "")
        } else {
            cardBody(c) {
                VStack(spacing: 6) {
                    ForEach(c.destinations) { d in
                        Button { openMode(d.route) } label: {
                            Label(d.title, systemImage: d.symbol)
                                .font(Theme.heading(12))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(modeTint(c).opacity(0.18)))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(modeTint(c).opacity(0.6)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(d.id)
                    }
                }
            }
        }
    }

    private func cardBody<Footer: View>(_ c: MatchModeCategory, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: c.symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(modeTint(c))
                .frame(width: 40, height: 40)
                .background(HexagonShape().fill(modeTint(c).opacity(0.18)))
                .overlay(HexagonShape().stroke(modeTint(c).opacity(0.6)))
            Text(c.title)
                .font(Theme.title(17))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(c.subtitle)
                .font(Theme.body(11))
                .foregroundStyle(modeTint(c))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            footer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(cornerRadius: 16, tint: modeTint(c).opacity(0.8))
        .contentShape(Rectangle())
    }

    /// 対戦フローを進めるカードの下段（ランクは現在のランク、ほかは報酬）。
    @ViewBuilder
    private func cardFooter(_ c: MatchModeCategory) -> some View {
        switch c {
        case .ranked:
            // カードが狭い（SE で約 100pt）ので、紋章とランク名・星を縦に並べる
            let rank = app.profile.rank
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    RankEmblemView(tier: rank.tier, size: 22)
                    Text(RankService.displayName(rank))
                        .font(Theme.heading(11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if rank.tier != .mythic {
                    RankStarsView(stars: rank.stars, maxStars: RankService.maxStars(rank.tier), size: 10)
                }
            }
            .accessibilityElement(children: .combine)
        case .classic:
            Label(L("勝利 220 · 敗北 110", "Win 220 · Loss 110"), systemImage: "star.circle.fill")
                .font(Theme.body(10))
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        default:
            EmptyView()
        }
    }

    /// 敵 AI の強さ（クラシック・ブロウル。ランクは自分のランクで決まる）。
    private var difficultyRow: some View {
        HStack(spacing: 8) {
            Text(L("敵 AI の強さ", "Enemy AI"))
                .font(Theme.heading(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
            ForEach(Difficulty.allCases, id: \.self) { d in
                let selected = model.difficulty == d
                Button {
                    FlowFX.tap(app)
                    withAnimation(.spring(duration: 0.25)) { model.difficulty = d }
                } label: {
                    Label(FlowText.difficulty(d), systemImage: FlowText.difficultySymbol(d))
                        .font(Theme.heading(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
                        .frame(maxWidth: 120, minHeight: 44)
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
            Text(Self.difficultyDetail(model.difficulty))
                .font(Theme.body(11))
                .foregroundStyle(Theme.cyan)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
        }
    }

    /// 難易度ごとの AI の特徴（DESIGN §10）。
    static func difficultyDetail(_ d: Difficulty) -> String {
        switch d {
        case .easy: return L("反応 0.6 秒・命中率 控えめ。はじめての方に。", "0.6s reactions, loose aim. Great for beginners.")
        case .normal: return L("反応 0.35 秒・標準的な立ち回り。", "0.35s reactions, standard play.")
        case .hard: return L("反応 0.15 秒・高い精度で集団行動をとる。", "0.15s reactions, precise aim and group tactics.")
        }
    }

    private func start(_ c: MatchModeCategory) {
        FlowFX.confirm(app)
        switch c {
        case .classic: model.startStandard()
        case .ranked: model.startRanked(profile: app.profile)
        case .brawl: model.startBrawl()
        case .arcade, .vsAI: break
        }
    }

    /// フローを閉じて各モードの画面へ。
    private func openMode(_ route: Route) {
        FlowFX.tap(app)
        app.router.isMatchFlowPresented = false
        app.router.push(route)
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
            return FlowText.mode(.ranked) + " · " + RankService.displayName(app.profile.rank)
        case .brawl:
            return FlowText.mode(.brawl) + " · " + L("敵 AI ", "Enemy AI ") + FlowText.difficulty(model.difficulty)
        case .standard:
            return FlowText.mode(.standard) + " · " + L("敵 AI ", "Enemy AI ") + FlowText.difficulty(model.difficulty)
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
                    Text(human ? PlayerNameRules.shown(slot.displayName) : (app.master.hero(slot.heroID).map { MasterText.hero($0) } ?? slot.heroID))
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
