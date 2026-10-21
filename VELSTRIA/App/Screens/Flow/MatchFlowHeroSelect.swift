import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI025 ヒーロー選択（通常戦）とロードアウト（ポジション・スキン・スペル・エンブレム）。

// MARK: - 2a. ヒーロー選択

struct HeroSelectStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 8) {
            MatchFlowHeader(title: L("ヒーロー選択", "Choose Your Hero"),
                            subtitle: L("通常戦 · 敵 AI ", "Standard · Enemy AI ") + FlowText.difficulty(model.difficulty),
                            backSymbol: "chevron.left", backID: "flow_back", onBack: back) {
                MatchFlowSteps(current: 1)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 8) {
                    RoleFilterBar(selection: $model.roleFilter)
                    HeroPickerGrid(heroes: heroes, cell: cell(for:), onTap: tap(_:))
                }
                LoadoutPanel(model: model) {
                    Button(action: next) {
                        Label(L("決定", "Confirm"), systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.heroID == nil)
                    .opacity(model.heroID == nil ? 0.5 : 1)
                    .accessibilityIdentifier("flow_next")
                }
                .frame(width: 292)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .alert(L("ヒーローを解放", "Unlock Hero"), isPresented: Binding(
            get: { model.unlockCandidate != nil }, set: { if !$0 { model.unlockCandidate = nil } }),
               presenting: model.unlockCandidate) { hero in
            if let item = unlockItem(hero) {
                Button(L("\(EconomyService.price(of: item).formatted()) コインで解放", "Unlock for \(EconomyService.price(of: item).formatted()) coins")) {
                    unlock(hero, item: item)
                }
            }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: { hero in
            Text(L("\(MasterText.hero(hero)) はまだ所持していません。所持コイン: \(app.profile.starlightCoin.formatted())",
                   "You don't own \(MasterText.hero(hero)) yet. Coins: \(app.profile.starlightCoin.formatted())"))
        }
    }

    /// 所持ヒーローを先頭に、ID 順。
    private var heroes: [HeroDef] {
        let all = app.master.heroes.filter { model.roleFilter == nil || $0.role == model.roleFilter }
        return all.filter { app.owns(heroID: $0.heroID) } + all.filter { !app.owns(heroID: $0.heroID) }
    }

    private func cell(for h: HeroDef) -> HeroGridCell {
        let owned = app.owns(heroID: h.heroID)
        return HeroGridCell(hero: h, selected: model.heroID == h.heroID, locked: !owned,
                            price: owned ? nil : unlockItem(h).map { EconomyService.price(of: $0) })
    }

    private func unlockItem(_ h: HeroDef) -> StoreItemDef? {
        app.master.store.first { $0.type == .heroUnlock && $0.grantID == h.heroID }
    }

    private func tap(_ h: HeroDef) {
        if app.owns(heroID: h.heroID) {
            FlowFX.tap(app)
            withAnimation(.spring(duration: 0.3)) { model.selectHero(h.heroID, profile: app.profile, master: app.master) }
        } else {
            FlowFX.tap(app)
            model.unlockCandidate = h
        }
    }

    private func unlock(_ hero: HeroDef, item: StoreItemDef) {
        var p = app.profile
        switch EconomyService.purchase(sku: item.sku, profile: &p, master: app.master) {
        case .success:
            app.profile = p
            FlowFX.reward(app)
            app.showToast(L("\(MasterText.hero(hero)) を解放しました", "Unlocked \(MasterText.hero(hero))"))
            model.selectHero(hero.heroID, profile: app.profile, master: app.master)
        case .insufficientFunds:
            FlowFX.error(app)
            app.showToast(L("コインが足りません", "Not enough coins"))
        case .alreadyOwned:
            model.selectHero(hero.heroID, profile: app.profile, master: app.master)
        case .limitReached, .invalid:
            FlowFX.error(app)
            app.showToast(L("購入できませんでした", "Purchase failed"))
        }
    }

    private func back() {
        FlowFX.back(app)
        model.step = .mode
    }

    private func next() {
        guard model.heroID != nil else { return }
        FlowFX.confirm(app)
        model.config = model.buildConfig(profile: app.profile, master: app.master)
        model.step = .ready
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
                        positionSection
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
                // ビルドの変更は対戦フロー（全画面）の下の画面に開いて見えなかったので置かない。変更はヒーロー詳細のビルドから
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
            Text(L("ホームの「エンブレム」で天賦の変更と一括設定ができます。", "Change talents and apply emblems to heroes from Emblems on the home screen."))
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
            VStack(spacing: 12) {
                HStack {
                    Text(L("バトルスキル", "Battle Skills")).font(Theme.heading(21)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    FlowCloseButton(identifier: "flow_spell_close") { model.spellPickerSlot = nil }
                }
                BattleSkillPicker(current: model.spells[0]) { id in
                    model.setSpell(id, slot: SpellLoadoutRules.selectableSlot)
                    if let heroID = model.heroID { app.profile.heroSpells[heroID] = model.spells }
                    model.spellPickerSlot = nil
                }
            }
            .padding(14)
            .frame(maxWidth: 900, maxHeight: 440)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.panelStroke))
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
        }
    }

}
