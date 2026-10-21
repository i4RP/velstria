import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI025 ヒーロー選択（クラシック・ブロウル）とロードアウト（ポジション・スキン・スペル・エンブレム・バトルプラン）。
// MLBB と同じく持ち時間があり（切れたらよく使うヒーローを優先して自動で選ぶ）、決めた後に 25 秒の最終調整。

// MARK: - 2a. ヒーロー選択

struct HeroSelectStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    @State private var remaining = FlowTiming.pickSeconds
    @State private var lane: LanePosition?
    @State private var confirmLeave = false

    var body: some View {
        VStack(spacing: 6) {
            PickPhaseHeader(phase: phaseText, seconds: remaining, urgent: remaining <= 5) {
                FlowCloseButton(identifier: "flow_close") { confirmLeave = true }
            } trailing: {
                if model.adjusting {
                    Button { FlowFX.confirm(app); model.launch(app: app) } label: {
                        Label(L("準備完了", "Ready"), systemImage: "checkmark").fixedSize()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("flow_confirm")
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if !model.adjusting {
                    VStack(spacing: 6) {
                        LaneFilterBar(selection: $lane)
                        HeroPickerGrid(heroes: heroes, cell: cell(for:), onTap: tap(_:))
                    }
                }
                LoadoutPanel(model: model) {
                    if !model.adjusting {
                        Button(action: lockIn) {
                            Label(L("決定", "Confirm"), systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.heroID == nil)
                        .opacity(model.heroID == nil ? 0.5 : 1)
                        .accessibilityIdentifier("flow_next")
                    }
                }
                .frame(width: model.adjusting ? nil : 292)
                .frame(maxWidth: model.adjusting ? 520 : nil)
                .overlay(alignment: .topTrailing) {
                    if let emote = model.myEmote { EmoteBubble(cosmeticID: emote, size: 48).offset(x: 6, y: -6) }
                }
            }
            QuickChatBar(model: model)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .task(id: model.adjusting) { await runClock() }
        .alert(L("ヒーロー選択を抜けますか？", "Leave hero selection?"), isPresented: $confirmLeave) {
            Button(L("抜ける", "Leave"), role: .destructive) {
                FlowFX.back(app)
                app.router.isMatchFlowPresented = false
            }
            Button(L("続ける", "Stay"), role: .cancel) {}
        }
    }

    private var phaseText: String {
        if model.adjusting {
            return L("試合はまもなく始まります。進む：", "The match is about to begin. Go: ") + FlowText.position(model.position)
        }
        let mode = model.kind == .brawl ? FlowText.mode(.brawl) : FlowText.mode(.standard)
        return mode + " · " + L("ヒーローを選んでください", "Choose your hero")
    }

    /// ゲームに出すヒーロー（タブのレーンに合うロールだけ）。全員が使える（ヒーローは売らない）。
    private var heroes: [HeroDef] {
        app.master.heroes.filter { LaneFilterBar.matches($0, lane: lane) }
    }

    private func cell(for h: HeroDef) -> HeroGridCell {
        HeroGridCell(hero: h, selected: model.heroID == h.heroID)
    }

    private func tap(_ h: HeroDef) {
        FlowFX.tap(app)
        withAnimation(.spring(duration: 0.3)) { model.selectHero(h.heroID, profile: app.profile, master: app.master) }
    }

    /// 持ち時間（ピック）→ 最終調整の 25 秒（0 で試合を始める）。
    private func runClock() async {
        remaining = model.adjusting ? FlowTiming.adjustSeconds : FlowTiming.pickSeconds
        while remaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            remaining -= 1
            if (1...3).contains(remaining) { app.audio.play(.countdown) }
        }
        if model.adjusting {
            model.launch(app: app)
        } else {
            // 時間切れ: 選んでいなければ、よく使うヒーローを優先して自動で選んで決める
            if model.heroID == nil {
                let roster = app.master.heroes.map(\.heroID)
                let id = DraftShowcase.favorites(app.profile, roster: roster).first ?? roster.first
                if let id { model.selectHero(id, profile: app.profile, master: app.master) }
                app.showToast(L("時間切れ: 自動で選びました", "Time's up: auto-picked"))
            }
            lockIn()
        }
    }

    private func lockIn() {
        guard model.heroID != nil, !model.adjusting else { return }
        FlowFX.confirm(app)
        app.audio.play(.lockIn)
        app.haptics.impact(.heavy)
        withAnimation(.spring(duration: 0.35)) { model.beginAdjusting() }
    }
}

// MARK: - 部品: ロールフィルタ・ヒーローグリッド

struct RoleFilterBar: View {
    @Binding var selection: Role?
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, title: L("すべて", "All"), symbol: "square.grid.2x2.fill")
                ForEach(Role.allCases.filter { r in app.master.heroes.contains { $0.role == r } }, id: \.self) { r in
                    chip(r, title: MasterText.role(r), symbol: Theme.roleSymbol(r))
                }
            }
        }
    }

    private func chip(_ role: Role?, title: String, symbol: String) -> some View {
        Button {
            FlowFX.tap(app)
            withAnimation(.spring(duration: 0.25)) { selection = role }
        } label: {
            FlowChip(title: title, symbol: symbol, selected: selection == role, tint: role.map { Theme.roleColor($0) } ?? Theme.gold)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flow_role_\(role?.rawValue ?? "all")")
        .accessibilityAddTraits(selection == role ? .isSelected : [])
    }
}

struct HeroPickerGrid: View {
    let heroes: [HeroDef]
    let cell: (HeroDef) -> HeroGridCell
    let onTap: (HeroDef) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 84), spacing: 6)], spacing: 8) {
                ForEach(heroes) { h in
                    Button {
                        onTap(h)
                    } label: {
                        cell(h)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("flow_hero_\(h.heroID)")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .glass(cornerRadius: 16)
    }
}

// MARK: - ロードアウト

struct LoadoutPanel<Footer: View>: View {
    @Bindable var model: MatchFlowModel
    @ViewBuilder var footer: () -> Footer
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    heroHeader
                    if model.heroID != nil {
                        // ランクのレーンはドラフトのレーン交換で変える（MLBB と同じ）。クラシック・ブロウルだけここで変えられる
                        if model.kind != .ranked { positionSection }
                        buildSection
                        spellSection
                        emblemSection
                        skinSection
                    }
                }
                .padding(12)
            }
            footer()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .glass(cornerRadius: 16, tint: Theme.gold.opacity(0.6))
    }

    @ViewBuilder private var heroHeader: some View {
        if let id = model.heroID, let h = app.master.hero(id) {
            HStack(spacing: 10) {
                HeroPortraitView(heroID: id, size: 58)
                    .glowPulse(Color(hue: Theme.heroHue(id), saturation: 0.7, brightness: 1), radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MasterText.hero(h))
                        .font(Theme.heading(16))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    RoleLabel(role: h.role, size: 11)
                    HStack(spacing: 1) {
                        Text(L("難度", "Difficulty")).font(Theme.body(10)).foregroundStyle(Theme.textSecondary).padding(.trailing, 3)
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < h.difficulty ? "star.fill" : "star").font(.system(size: 8)).foregroundStyle(Theme.gold)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("難度 \(h.difficulty) / 5", "Difficulty \(h.difficulty) of 5"))
                }
                Spacer(minLength: 0)
            }
            .id(id)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            Label(L("ヒーローを選んでください", "Choose a hero"), systemImage: "hand.tap.fill")
                .font(Theme.heading(14))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 58)
        }
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("ポジション", "Position"), symbol: "map.fill",
                             trailing: model.kind == .ranked ? L("味方と入れ替え", "Swaps with ally") : L("ロールから自動", "Auto from role"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                ForEach(LanePosition.allCases, id: \.self) { p in
                    Button {
                        FlowFX.tap(app)
                        withAnimation(.spring(duration: 0.25)) { model.setPosition(p) }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: FlowText.positionSymbol(p)).font(.system(size: 15, weight: .bold))
                            Text(FlowText.position(p)).font(.system(size: 9, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(model.position == p ? Color.black.opacity(0.85) : Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(model.position == p ? AnyShapeStyle(Theme.cyan) : AnyShapeStyle(Color.white.opacity(0.07))))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(FlowText.position(p))
                    .accessibilityAddTraits(model.position == p ? .isSelected : [])
                    .accessibilityIdentifier("flow_position_\(p.rawValue)")
                }
            }
        }
    }

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("ビルド", "Build"), symbol: "shield.fill")
            if let heroID = model.heroID {
                HStack(spacing: 3) {
                    ForEach(Array(BuildRules.current(for: heroID, profile: app.profile, master: app.master).enumerated()), id: \.offset) { _, id in
                        if let item = app.master.item(id) { ItemIconView(item: item, size: 32) }
                    }
                }
                // バトルプランの切り替え（MLBB の最終調整と同じく、ここで変えられる。装備とエンブレムの既定が変わる）
                let plans = BuildRules.plans(for: heroID)
                if !plans.isEmpty {
                    let active = BuildRules.activePlanIndex(for: heroID, profile: app.profile)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(plans.indices, id: \.self) { i in
                                Button {
                                    FlowFX.tap(app)
                                    BuildRules.choosePlan(i, for: heroID, profile: &app.profile)
                                } label: {
                                    FlowChip(title: BuildRules.planName(plans[i]), symbol: "list.bullet.rectangle", selected: active == i, tint: Theme.gold)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("flow_plan_\(i)")
                            }
                        }
                    }
                }
            }
        }
    }

    private var spellSection: some View {
        let id = model.spells.first ?? "BS01"
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: L("バトルスキル", "Battle Skill"), symbol: "wand.and.stars")
            HStack(spacing: 12) {
                SpellIconView(spellID: id, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(FlowText.spellName(id)).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                    Text(L("追加スキル · 1枠", "One extra skill")).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .center)
            Button { FlowFX.tap(app); model.spellPickerSlot = SpellLoadoutRules.selectableSlot } label: {
                Label(L("変更", "Change"), systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.body(11)).foregroundStyle(Theme.cyan)
            }.buttonStyle(.plain).frame(minHeight: 30).accessibilityIdentifier("flow_spell_0")
            Text(L("リコール・回復は常時使用可能", "Recall and Recovery always available"))
                .font(Theme.body(9)).foregroundStyle(Theme.textSecondary)
        }
    }

    /// このヒーローで使うエンブレム（エンブレム画面の一括設定で付けたもの、無ければ選んだバトルプランのもの）。
    private var emblemSection: some View {
        let emblem = model.emblem(profile: app.profile, master: app.master)
        let custom = model.heroID.map { EmblemMath.custom(for: $0, profile: app.profile) != nil } ?? false
        return VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("エンブレム", "Emblem"), symbol: "shield.checkered",
                             trailing: custom ? L("一括設定", "Custom") : L("バトルプラン", "Battle plan"))
            if let emblem {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(EmblemMath.setName(emblem.set))  Lv\(emblem.level)")
                        .font(Theme.heading(12))
                        .foregroundStyle(EmblemStyle.color(emblem.set))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    EmblemLoadoutBadge(emblem: emblem, compact: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .glass(cornerRadius: 10)
                .accessibilityIdentifier("flow_emblem")
            }
            // エンブレムのセットの切り替え（MLBB の最終調整と同じ。セットの今の天賦をこのヒーローに付ける。「プラン」はバトルプランのもの）
            if let heroID = model.heroID {
                let customSet = EmblemMath.custom(for: heroID, profile: app.profile)?.set
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            FlowFX.tap(app)
                            EmblemMath.clearCustom(heroID: heroID, profile: &app.profile)
                        } label: {
                            FlowChip(title: L("プラン", "Plan"), symbol: "list.bullet.rectangle", selected: customSet == nil, tint: Theme.gold)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("flow_emblem_plan")
                        ForEach(EmblemSetID.allCases.filter { EmblemMath.isUnlocked($0, profile: app.profile) }, id: \.self) { set in
                            Button {
                                FlowFX.tap(app)
                                EmblemMath.apply(set: set, to: [heroID], profile: &app.profile)
                            } label: {
                                FlowChip(title: EmblemMath.setName(set), symbol: EmblemStyle.setSymbol(set), selected: customSet == set,
                                         tint: EmblemStyle.color(set))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("flow_emblem_\(set.rawValue)")
                        }
                    }
                }
            }
            Text(L("天賦の変更はホームの「エンブレム」から。", "Change talents from Emblems on the home screen."))
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var skinSection: some View {
        let skins = model.heroID.map { id in
            app.master.cosmetics.filter { $0.type == .heroSkin && $0.heroID == id && app.owns(cosmeticID: $0.cosmeticID) }
        } ?? []
        return VStack(alignment: .leading, spacing: 5) {
            SectionTitle(title: L("スキン", "Skin"), symbol: "sparkles")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    skinChip(nil, title: L("デフォルト", "Default"), color: Theme.textSecondary)
                    ForEach(skins) { c in
                        skinChip(c.cosmeticID, title: MasterText.cosmetic(c), color: Theme.rarityColor(c.rarity))
                    }
                }
            }
            if skins.isEmpty {
                Text(L("このヒーローのスキンはストアで入手できます。", "Skins for this hero are available in the Store."))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func skinChip(_ id: String?, title: String, color: Color) -> some View {
        Button {
            FlowFX.tap(app)
            model.skinID = id
        } label: {
            FlowChip(title: title, symbol: id == nil ? "person.fill" : "sparkles", selected: model.skinID == id, tint: color)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flow_skin_\(id ?? "default")")
    }
}

// MARK: - スペル選択

struct SpellPickerOverlay: View {
    @Bindable var model: MatchFlowModel
    let slot: Int
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { model.spellPickerSlot = nil }
                .accessibilityHidden(true)
            // MLBB の「バトルスキル」のポップアップ: 中央の見出しと右上の ×
            VStack(spacing: 10) {
                ZStack {
                    Text(L("バトルスキル", "Battle Skills")).font(Celestial.title(20)).foregroundStyle(Theme.textPrimary)
                    HStack {
                        Spacer()
                        FlowCloseButton(identifier: "flow_spell_close") { model.spellPickerSlot = nil }
                    }
                }
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Celestial.ice.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 0.7)
                BattleSkillPicker(current: model.spells[0], lane: model.position) { id in
                    model.setSpell(id, slot: SpellLoadoutRules.selectableSlot)
                    if let heroID = model.heroID { app.profile.heroSpells[heroID] = model.spells }
                    model.spellPickerSlot = nil
                }
            }
            .padding(14)
            .frame(maxWidth: 900, maxHeight: 440)
            .background(HomeChamfer(cut: 12).fill(Celestial.ink.opacity(0.96)))
            .overlay(HomeChamfer(cut: 12).stroke(Celestial.ice.opacity(0.6), lineWidth: 0.8))
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
        }
    }

}
