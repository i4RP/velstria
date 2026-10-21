import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI021〜025 対戦前フロー（全画面。MLBB の手順）。
// 1. モード選択 → 2. レーン選択（クラシック・ランク）→ 3. マッチング →「マッチ成立」で入場 →
// 4a. ヒーロー選択（クラシック・ブロウル） / 4b. ドラフト（ランク）→ 5. 最終調整（25 秒）→ 戦闘。相手は今のところ AI。

/// 対戦フローの状態（画面間で共有）。
@Observable
@MainActor
final class MatchFlowModel {
    enum Kind: Equatable { case standard, ranked, brawl }
    /// ピックの後の最終調整（MLBB の 25 秒）は heroSelect・draft の中の段（adjusting）。
    enum Step: Int, Equatable { case mode, lane, matching, heroSelect, draft }

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

    /// マッチングの前に選ぶレーン（MLBB 2025-06 から。主と副。主が nil = 全部）。ドラフトのポジションの割り当てに使う。
    var lanePrimary: LanePosition?
    var laneSecondary: LanePosition?
    /// ドラフト・ヒーロー選択のチャット欄（定型文だけ）。
    var chat: [FlowChatLine] = []
    /// 自分が出したエモート（数秒で消える。EmoteTiming）。
    var myEmote: String?

    var draft: DraftEngine?
    /// ドラフトでプレイヤーが仮選択しているヒーロー。
    var draftHover: String?
    /// AI 手番で決めた選択（演出中に画面が作り直されても同じ選択を使い、乱数を二重に進めない）。
    var aiPending: (turnIndex: Int, heroID: String?)?
    /// 出撃準備で表示・起動する構成。
    var config: MatchConfig?

    /// ピックの後の最終調整（MLBB の 25 秒。スキン・エンブレム・スペル・バトルプランを変えられる）。
    var adjusting = false
    private var launched = false

    var spellPickerSlot: Int?
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
            // マッチングの前に選んだレーン（全部なら、ヒーローのロールに合うレーン）
            position = lanePrimary ?? MatchFactory.defaultPosition(for: role)
        }
        // 担当レーンで使えないスキル（ジャングル以外の狩猟）は瞬歩に戻す
        spells = SpellLoadoutRules.forLane(SpellLoadoutRules.effective(heroID: id, profile: profile), lane: position)
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
        spells = SpellLoadoutRules.forLane(spells, lane: p)
        if kind == .ranked { draft?.setPlayerPosition(p) }
    }

    /// 試合で使うエンブレム（一括設定で付けたもの、無ければ選んだバトルプランのもの。EmblemMath.loadout）。
    func emblem(profile: Profile, master: MasterData) -> EmblemLoadout? {
        guard let heroID else { return nil }
        return EmblemMath.loadout(for: heroID, profile: profile, master: master)
    }

    /// モードを選んだ: クラシック・ランクはレーン選択へ、ブロウル（単レーン）はそのままマッチングへ。
    func chooseMode(_ k: Kind) {
        kind = k
        draft = nil
        config = nil
        chat = []
        step = k == .brawl ? .matching : .lane
    }

    /// マッチ成立で入場した: ランクはドラフト、ほかはヒーロー選択へ。
    func beginPicking(profile: Profile) {
        switch kind {
        case .ranked: startRanked(profile: profile)
        case .standard: startStandard()
        case .brawl: startBrawl()
        }
    }

    /// ドラフトの自分の手番（試合ごとに変わる。UI テストに限り -draftSlot <1〜5> で固定できる）。
    var draftSlot: Int {
        if DebugLaunch.isUITesting, let s = DebugLaunch.value(after: "-draftSlot").flatMap({ Int($0) }) { return min(4, max(0, s - 1)) }
        return DraftEngine.playerSlot(seed: seed)
    }

    func startRanked(profile: Profile) {
        kind = .ranked
        draft = DraftEngine(seed: seed, playerSlot: draftSlot, playerLane: lanePrimary)
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

    /// ピックが決まった: 最終調整（25 秒）へ。
    func beginAdjusting() {
        adjusting = true
    }

    /// 最終調整を終えて試合を始める（ロードアウトを保存して戦闘へ。構成は最終調整の変更を入れて作り直す）。
    func launch(app: AppModel) {
        guard !launched, let heroID, let config = buildConfig(profile: app.profile, master: app.master) else { return }
        launched = true
        self.config = config
        var p = app.profile
        p.lastPickedHeroID = heroID
        if kind == .standard { p.preferredDifficulty = difficulty }
        p.heroSpells[heroID] = spells
        if let skin = skinID {
            p.equippedSkins[heroID] = skin
        } else {
            p.equippedSkins.removeValue(forKey: heroID)
        }
        app.profile = p
        app.startBattle(BattleLaunch(config: config, countsForRank: kind == .ranked))
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
            CelestialBackdrop()
            Group {
                switch model.step {
                case .mode: MatchModeStep(model: model)
                case .lane: LaneSelectStep(model: model)
                case .matching: MatchingStep(model: model)
                case .heroSelect: HeroSelectStep(model: model)
                case .draft: DraftStep(model: model)
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
            case .mode, .lane, .matching: app.audio.playMusic(.menu)
            case .heroSelect: app.audio.playMusic(.lobby)
            case .draft: app.audio.playMusic(.draft)
            }
        }
        .onDisappear {
            // 試合へ進まずに閉じたらホームの曲へ戻す（試合へ進む時はロード画面が曲を変える）
            if app.activeBattle == nil { app.audio.playMusic(.menu) }
        }
        .onAppear {
            model.configure(profile: app.profile, master: app.master)
            // もう一度・ランクの画面から: MLBB と同じくレーン選択（ブロウルはマッチング）から
            switch MatchFlowIntent.consume() {
            case .standard(let d)?:
                model.difficulty = d
                model.chooseMode(.standard)
            case .ranked?:
                model.chooseMode(.ranked)
            case .brawl(let d)?:
                model.difficulty = d
                model.chooseMode(.brawl)
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

// MARK: - 1. モード選択（UI021。MLBB の大きなカード）

/// モード選択の並び（MLBB と同じく、遊べるモードはすべてここから入る）。
enum MatchModeCategory: String, CaseIterable, Identifiable {
    case classic, ranked, brawl, magicChess, arcade, vsAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return L("クラシック", "Classic")
        case .ranked: return L("ランク", "Ranked")
        case .brawl: return L("ブロウル", "Brawl")
        case .magicChess: return L("マジックチェス", "Magic Chess")
        case .arcade: return L("アーケード", "Arcade")
        case .vsAI: return L("VS AI & カスタム", "VS AI & Custom")
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return L("5v5 · 3 レーン", "5v5 · 3 lanes")
        case .ranked: return L("ドラフト · 5v5", "Draft · 5v5")
        case .brawl: return L("5v5 · 単レーン", "5v5 · 1 lane")
        case .magicChess: return L("8 人のオートバトル", "8-player auto battle")
        case .arcade: return L("期間限定・変則ルール", "Limited & variant rules")
        case .vsAI: return L("カスタム・練習場", "Custom & practice")
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "flag.2.crossed.fill"
        case .ranked: return "crown.fill"
        case .brawl: return "burst.fill"
        case .magicChess: return "square.grid.3x3.fill"
        case .arcade: return "gamecontroller.fill"
        case .vsAI: return "cpu"
        }
    }

    /// 大きなカード（押すと対戦へ進む・画面を開く）か、右の小さなカード（中のボタンで各画面へ）か。
    var isLarge: Bool { self != .arcade && self != .vsAI }

    /// カードの識別子。
    var identifier: String? {
        switch self {
        case .classic: return "flow_mode_standard"
        case .ranked: return "flow_mode_ranked"
        case .brawl: return "flow_mode_brawl"
        case .magicChess: return "flow_mode_magicChess"
        case .arcade, .vsAI: return nil
        }
    }

    /// 小さなカードの中のボタン（押すとフローを閉じて各画面へ）。
    var destinations: [MatchModeDestination] {
        switch self {
        case .classic, .ranked, .brawl, .magicChess: return []
        case .arcade:
            return [MatchModeDestination(route: .rising, title: L("ライジング", "Rising"), symbol: "chart.line.uptrend.xyaxis", id: "flow_mode_rising")]
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
            MatchFlowHeader(title: L("対戦モード", "Select Mode"), subtitle: nil,
                            backSymbol: "xmark", backID: "flow_close", onBack: close) { EmptyView() }
            HStack(alignment: .top, spacing: 8) {
                ForEach(MatchModeCategory.allCases.filter(\.isLarge)) { largeCard($0) }
                VStack(spacing: 8) {
                    ForEach(MatchModeCategory.allCases.filter { !$0.isLarge }) { smallCard($0) }
                }
                .frame(width: 150)
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
        case .classic: return Celestial.ice
        case .ranked: return Theme.gold
        case .brawl: return Color(red: 1.0, green: 0.55, blue: 0.18)
        case .magicChess: return Color(red: 0.72, green: 0.52, blue: 1.0)
        case .arcade: return Theme.success
        case .vsAI: return Color(red: 0.56, green: 0.70, blue: 1.0)
        }
    }

    /// 大きなカード（MLBB のモードの絵札）。ランクは今のティアの紋章と星。
    private func largeCard(_ c: MatchModeCategory) -> some View {
        let tint = modeTint(c)
        let featured = c == .ranked
        return Button { start(c) } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 60))
                    if featured {
                        RankCrest(tier: app.profile.rank.tier, size: 76)
                    } else {
                        Image(systemName: c.symbol)
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(tint)
                            .shadow(color: tint.opacity(0.7), radius: 8)
                    }
                }
                .frame(height: 96)
                Text(c.title)
                    .font(Celestial.title(featured ? 22 : 19))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if featured {
                    let rank = app.profile.rank
                    Text(RankService.displayName(rank)).font(Celestial.heading(12)).foregroundStyle(Theme.gold)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if rank.tier == .mythic {
                        Label("\(rank.stars)", systemImage: "star.fill").font(Theme.body(11)).foregroundStyle(Theme.gold)
                    } else {
                        RankStarsView(stars: rank.stars, maxStars: RankService.maxStars(rank.tier), size: 11)
                    }
                } else {
                    Text(c.subtitle).font(Theme.body(11)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                if c == .classic {
                    HStack(spacing: 4) {
                        CurrencyIcon(kind: .coin, size: 12)
                        Text(L("勝利 220 · 敗北 110", "Win 220 · Loss 110"))
                            .font(Theme.body(10)).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(cornerRadius: 16, tint: tint.opacity(0.85), highlighted: featured)
            .shadow(color: featured ? Theme.gold.opacity(0.35) : .clear, radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(c.title)
        .accessibilityIdentifier(c.identifier ?? c.rawValue)
    }

    /// 右の小さなカード（アーケード・VS AI & カスタム）。
    private func smallCard(_ c: MatchModeCategory) -> some View {
        let tint = modeTint(c)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: c.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                Text(c.title).font(Celestial.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            }
            ForEach(c.destinations) { d in
                Button { openMode(d.route) } label: {
                    Label(d.title, systemImage: d.symbol)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(HomeChamfer(cut: 6).fill(tint.opacity(0.16)))
                        .overlay(HomeChamfer(cut: 6).stroke(tint.opacity(0.55), lineWidth: 0.6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(d.id)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glass(cornerRadius: 14, tint: tint.opacity(0.8))
    }

    /// 敵 AI の強さ（クラシック・ブロウル。ランクは自分のランクで決まる）。
    private var difficultyRow: some View {
        HStack(spacing: 8) {
            Text(L("敵 AI の強さ", "Enemy AI"))
                .font(Celestial.heading(12))
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
                        .font(Celestial.heading(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color(red: 0.16, green: 0.10, blue: 0.03) : Theme.textPrimary)
                        .frame(maxWidth: 120, minHeight: 44)
                        .background(HomeChamfer(cut: 7).fill(selected ? AnyShapeStyle(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                                                                       : AnyShapeStyle(Celestial.ink.opacity(0.8))))
                        .overlay(HomeChamfer(cut: 7).stroke(selected ? HomeStyle.goldLight : Celestial.ice.opacity(0.4), lineWidth: selected ? 1 : 0.6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FlowText.difficulty(d))
                .accessibilityIdentifier("flow_difficulty_\(d.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Text(Self.difficultyDetail(model.difficulty))
                .font(Theme.body(11))
                .foregroundStyle(Celestial.ice)
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
        switch c {
        case .classic: FlowFX.confirm(app); model.chooseMode(.standard)
        case .ranked: FlowFX.confirm(app); model.chooseMode(.ranked)
        case .brawl: FlowFX.confirm(app); model.chooseMode(.brawl)
        case .magicChess: openMode(.magicChess)
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
