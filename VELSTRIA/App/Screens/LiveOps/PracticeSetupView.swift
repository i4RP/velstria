import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI072 練習場の準備（ヒーロー選択と練習オプション）。

enum PracticeSetup {
    static let levelRange = 1...Balance.maxLevel

    /// 初期選択ヒーロー（直近使用 → 所持の先頭 → マスター先頭）。
    static func defaultHeroID(profile: Profile, master: MasterData = .shared) -> String {
        if let last = profile.lastPickedHeroID, master.hero(last) != nil { return last }
        if let owned = profile.ownedHeroIDs.first(where: { master.hero($0) != nil }) { return owned }
        return master.heroes.first?.heroID ?? "H001"
    }

    /// ロードアウト（スペル・ルーン・スキン・自動習得）を反映した練習場の設定。未所持ヒーローも練習可能。
    static func config(heroID: String, options: PracticeOptions, profile: Profile, seed: UInt64,
                       master: MasterData = .shared) -> MatchConfig {
        var opts = options
        opts.startLevel = min(levelRange.upperBound, max(levelRange.lowerBound, opts.startLevel))
        let name = profile.displayName.isEmpty ? L("プレイヤー", "Player") : profile.displayName
        var config = MatchFactory.practiceMatch(humanHeroID: heroID, humanName: name, options: opts,
                                                tutorial: false, seed: seed, master: master)
        guard let i = config.players.firstIndex(where: { $0.controller == .human }) else { return config }
        if let spells = spells(heroID: heroID, profile: profile, master: master) {
            config.players[i].spells = spells
        }
        config.players[i].runes = runes(profile: profile, master: master)
        if let skin = profile.equippedSkins[heroID], profile.ownedCosmeticIDs.contains(skin) {
            config.players[i].skinID = skin
        }
        config.players[i].autoLevelSkills = profile.settings.autoLevelSkills
        return config
    }

    /// プレイヤーのスペル設定（不正なら nil = 既定を使う）。
    static func spells(heroID: String, profile: Profile, master: MasterData = .shared) -> [String]? {
        let chosen = profile.heroSpells[heroID] ?? profile.defaultSpells
        guard chosen.count == 2, Set(chosen).count == 2, chosen.allSatisfy({ master.spell($0) != nil }) else { return nil }
        return chosen
    }

    /// 選択中ルーンページの有効なルーン。
    static func runes(profile: Profile, master: MasterData = .shared) -> [String] {
        guard profile.runePages.indices.contains(profile.selectedRunePage) else { return [] }
        return profile.runePages[profile.selectedRunePage].runeIDs.filter { !$0.isEmpty && master.rune($0) != nil }
    }

    static func newSeed() -> UInt64 { UInt64.random(in: 1...UInt64(UInt32.max)) }
}

struct PracticeSetupView: View {
    @Environment(AppModel.self) private var app
    @State private var heroID: String?
    @State private var roleFilter: Role?
    @State private var options = PracticeOptions()

    var body: some View {
        let selected = heroID ?? PracticeSetup.defaultHeroID(profile: app.profile, master: app.master)
        ScreenScaffold(title: L("練習場", "Practice")) {
            HStack(alignment: .top, spacing: 14) {
                heroPicker(selected: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                optionsPanel(selected: selected)
                    .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    // MARK: ヒーロー選択

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
                Text(L("練習場では未所持のヒーローも使用できます。", "All heroes are available in Practice, owned or not."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func roleChip(_ role: Role?) -> some View {
        let selected = roleFilter == role
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
            .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(selected ? AnyShapeStyle(role.map { Theme.roleColor($0) } ?? Theme.cyan)
                                                : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(selected ? Color.white.opacity(0.5) : Theme.panelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("practice_role_\(role?.rawValue ?? "all")")
    }

    private func heroCell(_ hero: HeroDef, selected: Bool) -> some View {
        Button {
            app.audio.play(.uiTap)
            app.haptics.tap()
            heroID = hero.heroID
        } label: {
            VStack(spacing: 4) {
                HeroPortraitView(heroID: hero.heroID, size: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 58 * 0.2, style: .continuous)
                            .stroke(selected ? Theme.gold : .clear, lineWidth: 3)
                    )
                    .shadow(color: selected ? Theme.gold.opacity(0.6) : .clear, radius: 6)
                    .overlay(alignment: .topLeading) {
                        if !app.owns(heroID: hero.heroID) {
                            Text(L("お試し", "Trial"))
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.cyan))
                                .offset(x: -4, y: -4)
                        }
                    }
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
        .accessibilityIdentifier("practice_hero_\(hero.heroID)")
    }

    // MARK: オプション

    private func optionsPanel(selected: String) -> some View {
        let def = app.master.hero(selected)
        return Panel(padding: 12) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    HeroPortraitView(heroID: selected, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.map { MasterText.hero($0) } ?? selected)
                            .font(Theme.heading(15))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let def {
                            Label(MasterText.role(def.role), systemImage: Theme.roleSymbol(def.role))
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.roleColor(def.role))
                        }
                    }
                    Spacer(minLength: 0)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                            optionToggle(L("ゴールド無限", "Infinite Gold"), symbol: "star.circle.fill", isOn: $options.infiniteGold,
                                         id: "practice_infinite_gold")
                            optionToggle(L("クールダウンなし", "No Cooldowns"), symbol: "timer", isOn: $options.noCooldowns,
                                         id: "practice_no_cooldowns")
                            optionToggle(L("ミニオン出現", "Minions"), symbol: "person.3.fill", isOn: $options.spawnMinions,
                                         id: "practice_spawn_minions")
                            optionToggle(L("ターゲット人形", "Dummies"), symbol: "figure.stand", isOn: $options.spawnDummies,
                                         id: "practice_spawn_dummies")
                        }
                        levelSlider
                    }
                }
                Button {
                    start(heroID: selected)
                } label: {
                    Label(L("練習開始", "Start Practice"), systemImage: "play.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                .accessibilityIdentifier("practice_start")
            }
        }
    }

    private func optionToggle(_ title: String, symbol: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
        }
        .toggleStyle(LiveOpsTileToggleStyle())
        .accessibilityIdentifier(id)
    }

    private var levelSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(L("開始レベル", "Starting Level"), systemImage: "arrow.up.circle.fill")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Lv \(options.startLevel)")
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { Double(options.startLevel) },
                                  set: { options.startLevel = Int($0.rounded()) }),
                   in: Double(PracticeSetup.levelRange.lowerBound)...Double(PracticeSetup.levelRange.upperBound), step: 1)
                .tint(Theme.gold)
                .frame(minHeight: 44)
                .accessibilityLabel(L("開始レベル", "Starting Level"))
                .accessibilityValue("Lv \(options.startLevel)")
                .accessibilityIdentifier("practice_level")
        }
    }

    private func start(heroID: String) {
        app.audio.play(.uiConfirm)
        let config = PracticeSetup.config(heroID: heroID, options: options, profile: app.profile,
                                          seed: PracticeSetup.newSeed(), master: app.master)
        app.startBattle(BattleLaunch(config: config))
    }
}
