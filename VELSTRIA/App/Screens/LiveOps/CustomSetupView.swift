import SwiftUI
import VelstriaCore

// 担当: ui-liveops。AI 対戦とカスタム: 側・味方/敵 AI の難易度・マップ・ヒーローを選んで起動する。
// 標準マップは customMatch（mode .custom）、乱闘マップは brawlMatch（mode .brawl）を使う
// （マップは mode から導出するため、ここで mode を分けておく）。

enum CustomSetup {
    enum MapKind: Int, Hashable, CaseIterable { case standard, brawl }

    static func newSeed() -> UInt64 { UInt64.random(in: 1...UInt64(UInt32.max)) }

    /// 選択内容から試合構成を作る（純関数・テスト可能）。
    static func config(heroID: String, side: Team, mapKind: MapKind,
                       allyDifficulty: Difficulty, enemyDifficulty: Difficulty,
                       profile: Profile, seed: UInt64, master: MasterData = .shared) -> MatchConfig {
        let name = profile.displayName.isEmpty ? "Player" : profile.displayName
        let spells = PracticeSetup.spells(heroID: heroID, profile: profile, master: master)
        let runes = PracticeSetup.runes(profile: profile, master: master)
        let skin = profile.equippedSkins[heroID].flatMap { profile.ownedCosmeticIDs.contains($0) ? $0 : nil }
        switch mapKind {
        case .brawl:
            return MatchFactory.brawlMatch(humanHeroID: heroID, humanName: name, humanTeam: side,
                                           humanSpells: spells, humanRunes: runes, humanSkin: skin,
                                           allyDifficulty: allyDifficulty, enemyDifficulty: enemyDifficulty,
                                           seed: seed, master: master)
        case .standard:
            return MatchFactory.customMatch(humanSide: side, humanHeroID: heroID, humanName: name,
                                            humanSpells: spells, humanRunes: runes, humanSkin: skin,
                                            allyDifficulty: allyDifficulty, enemyDifficulty: enemyDifficulty,
                                            seed: seed, master: master)
        }
    }

    static func mapName(_ kind: MapKind) -> String {
        switch kind {
        case .standard: return L("星環の戦場（3 レーン）", "Star Ring (3 lanes)")
        case .brawl: return L("乱闘（単レーン）", "Brawl (single lane)")
        }
    }
}

struct CustomSetupView: View {
    @Environment(AppModel.self) private var app
    @State private var heroID: String?
    @State private var roleFilter: Role?
    @State private var side: Team = .blue
    @State private var mapKind: CustomSetup.MapKind = .standard
    @State private var allyDifficulty: Difficulty = .normal
    @State private var enemyDifficulty: Difficulty = .hard

    var body: some View {
        let selected = heroID ?? PracticeSetup.defaultHeroID(profile: app.profile, master: app.master)
        ScreenScaffold(title: L("AI 対戦とカスタム", "AI & Custom")) {
            HStack(alignment: .top, spacing: 14) {
                heroPicker(selected: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                optionsPanel(selected: selected)
                    .frame(width: 320)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    // MARK: ヒーロー選択（練習場と同じ見た目）

    private func heroPicker(selected: String) -> some View {
        let heroes = app.master.heroes.filter { roleFilter == nil || $0.role == roleFilter }
        return Panel(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        roleChip(nil)
                        ForEach(Role.allCases, id: \.self) { roleChip($0) }
                    }
                }
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 8)], spacing: 8) {
                        ForEach(heroes) { hero in
                            heroCell(hero, selected: hero.heroID == selected)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text(L("カスタムでは未所持のヒーローも使用できます。報酬・ランクはつきません。",
                       "All heroes are available in Custom. No rewards or rank."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func roleChip(_ role: Role?) -> some View {
        let isSel = roleFilter == role
        let title = role.map { MasterText.role($0) } ?? L("すべて", "All")
        return Button {
            app.audio.play(.uiTap)
            roleFilter = role
        } label: {
            HStack(spacing: 4) {
                if let role { Image(systemName: Theme.roleSymbol(role)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isSel ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSel ? AnyShapeStyle(role.map { Theme.roleColor($0) } ?? Theme.cyan)
                                            : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(isSel ? Color.white.opacity(0.5) : Theme.panelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSel ? .isSelected : [])
        .accessibilityIdentifier("custom_role_\(role?.rawValue ?? "all")")
    }

    private func heroCell(_ hero: HeroDef, selected: Bool) -> some View {
        Button {
            app.audio.play(.uiTap)
            app.haptics.tap()
            heroID = hero.heroID
        } label: {
            VStack(spacing: 4) {
                HeroPortraitView(heroID: hero.heroID, size: 58)
                    .overlay(RoundedRectangle(cornerRadius: 58 * 0.2, style: .continuous)
                        .stroke(selected ? Theme.gold : .clear, lineWidth: 3))
                    .shadow(color: selected ? Theme.gold.opacity(0.6) : .clear, radius: 6)
                Text(MasterText.hero(hero))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(MasterText.hero(hero)), \(MasterText.role(hero.role))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("custom_hero_\(hero.heroID)")
    }

    // MARK: オプション

    private func optionsPanel(selected: String) -> some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                labeledSegment(L("あなたの陣営", "Your Side"),
                               options: [Team.blue, .red].map {
                                   LiveOpsSegmentOption(value: $0, title: LiveOpsFormat.teamName($0),
                                                        identifier: "custom_side_\($0.rawValue)")
                               }, selection: $side)
                labeledSegment(L("マップ", "Map"),
                               options: CustomSetup.MapKind.allCases.map {
                                   LiveOpsSegmentOption(value: $0, title: $0 == .brawl ? L("乱闘", "Brawl") : L("標準", "Standard"),
                                                        identifier: "custom_map_\($0.rawValue)")
                               }, selection: $mapKind)
                Text(CustomSetup.mapName(mapKind))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.cyan)
                labeledSegment(L("味方 AI", "Allied AI"),
                               options: Difficulty.allCases.map {
                                   LiveOpsSegmentOption(value: $0, title: LiveOpsFormat.difficultyName($0),
                                                        identifier: "custom_ally_\($0.rawValue)")
                               }, selection: $allyDifficulty)
                labeledSegment(L("敵 AI", "Enemy AI"),
                               options: Difficulty.allCases.map {
                                   LiveOpsSegmentOption(value: $0, title: LiveOpsFormat.difficultyName($0),
                                                        identifier: "custom_enemy_\($0.rawValue)")
                               }, selection: $enemyDifficulty)
                Spacer(minLength: 0)
                Button {
                    start(heroID: selected)
                } label: {
                    Label(L("対戦開始", "Start Match"), systemImage: "play.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                .accessibilityIdentifier("custom_start")
            }
        }
    }

    private func labeledSegment<Value: Hashable>(_ title: String, options: [LiveOpsSegmentOption<Value>],
                                                 selection: Binding<Value>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
            LiveOpsSegmented(options: options, selection: selection, onChange: { _ in app.audio.play(.uiTap) })
        }
    }

    private func start(heroID: String) {
        app.audio.play(.uiConfirm)
        let config = CustomSetup.config(heroID: heroID, side: side, mapKind: mapKind,
                                        allyDifficulty: allyDifficulty, enemyDifficulty: enemyDifficulty,
                                        profile: app.profile, seed: CustomSetup.newSeed(), master: app.master)
        app.startBattle(BattleLaunch(config: config))
    }
}
