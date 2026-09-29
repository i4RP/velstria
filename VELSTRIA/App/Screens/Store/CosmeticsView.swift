import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI058 コスメ装備（ヒーロー別スキン・帰還/出現/キル演出・アバターフレーム）。

struct CosmeticsView: View {
    @Environment(AppModel.self) private var app
    @State private var type: CosmeticType = .heroSkin
    @State private var heroID: String?

    static let editableTypes: [CosmeticType] = [.heroSkin, .recall, .spawn, .killEffect, .avatarFrame]
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    var body: some View {
        ScreenScaffold(title: L("コスメ", "Cosmetics")) {
            HStack(alignment: .top, spacing: 12) {
                typeRail
                    .frame(width: 150)
                Group {
                    if type == .heroSkin {
                        skinEditor
                    } else {
                        effectEditor(type)
                    }
                }
                .id(type)
                .transition(.opacity)
            }
            .padding(.horizontal, 20)
            .animation(.easeInOut(duration: 0.2), value: type)
        }
        .onAppear {
            if heroID == nil {
                let owned = app.master.heroes.filter { app.owns(heroID: $0.heroID) }
                heroID = owned.first { !CosmeticInfo.skins(heroID: $0.heroID, master: app.master).isEmpty }?.heroID
                    ?? owned.first?.heroID
            }
        }
    }

    // MARK: 種類

    private var typeRail: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Self.editableTypes, id: \.self) { t in
                    railButton(title: CollectionStyle.cosmeticTypeName(t), symbol: CollectionStyle.cosmeticTypeSymbol(t),
                               selected: type == t, id: "cosmetics_type_\(t.rawValue)") {
                        app.haptics.tap()
                        type = t
                    }
                }
                railButton(title: CollectionStyle.cosmeticTypeName(.emote), symbol: CollectionStyle.cosmeticTypeSymbol(.emote),
                           selected: false, id: "cosmetics_emotes", trailing: "arrow.up.right") {
                    app.router.push(.emotes)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func railButton(title: String, symbol: String, selected: Bool, id: String, trailing: String? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : StoreCategory.effects.color)
                    .frame(width: 18)
                Text(title)
                    .font(Theme.body(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
                Spacer(minLength: 0)
                if let trailing {
                    Image(systemName: trailing).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? AnyShapeStyle(StoreCategory.effects.color) : AnyShapeStyle(Color.white.opacity(0.06))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    // MARK: スキン

    private var skinEditor: some View {
        let owned = app.master.heroes.filter { app.owns(heroID: $0.heroID) }
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(owned) { h in
                        heroButton(h)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if let heroID, let hero = app.master.hero(heroID) {
                let skins = CosmeticInfo.skins(heroID: heroID, master: app.master)
                let equippedID = app.profile.equippedSkins[heroID]
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        CollectionSectionTitle(title: MasterText.hero(hero), symbol: Theme.roleSymbol(hero.role),
                                               trailing: L("スキン \(skins.count + 1) 種", "\(skins.count + 1) looks"))
                        LazyVGrid(columns: columns, spacing: 10) {
                            optionCell(preview: AnyView(HeroPortraitView(heroID: heroID, size: 64)), name: L("デフォルト", "Default"),
                                       state: equippedID == nil ? .equipped : .owned, id: "cosmetic_default_skin") {
                                var p = app.profile
                                CosmeticInfo.unequip(.heroSkin, heroID: heroID, profile: &p)
                                app.profile = p
                            }
                            ForEach(skins) { c in
                                cosmeticOption(c)
                            }
                        }
                        if skins.isEmpty {
                            Text(L("このヒーローのスキンは今後のシーズンで登場予定です。", "Skins for this hero are coming in future seasons."))
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func heroButton(_ h: HeroDef) -> some View {
        let selected = heroID == h.heroID
        let hasSkins = !CosmeticInfo.skins(heroID: h.heroID, master: app.master).isEmpty
        return Button {
            app.haptics.tap()
            heroID = h.heroID
        } label: {
            ZStack(alignment: .topTrailing) {
                HeroPortraitView(heroID: h.heroID, size: 38, showsRole: false)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.gold : Color.clear, lineWidth: 2.5))
                    .opacity(selected ? 1 : 0.7)
                if hasSkins {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(3)
                        .background(Circle().fill(StoreCategory.skins.color))
                        .offset(x: 3, y: -3)
                }
            }
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MasterText.hero(h))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("cosmetics_hero_\(h.heroID)")
    }

    // MARK: 演出・フレーム

    private func effectEditor(_ type: CosmeticType) -> some View {
        let all = app.master.cosmetics.filter { $0.type == type }
        let owned = all.filter { app.owns(cosmeticID: $0.cosmeticID) }
        let locked = all.filter { !app.owns(cosmeticID: $0.cosmeticID) }
        let equipped = CosmeticInfo.equippedID(type, profile: app.profile).flatMap { app.master.cosmetic($0) }
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(L("装備中", "Equipped")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                if let equipped {
                    CosmeticPreviewView(cosmetic: equipped, size: 118, animated: true)
                    Text(MasterText.cosmetic(equipped))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                } else {
                    defaultPreview(type, size: 118)
                    Text(L("デフォルト", "Default")).font(Theme.body(11)).foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 130)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.panelStroke, lineWidth: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    CollectionSectionTitle(title: CollectionStyle.cosmeticTypeName(type), symbol: CollectionStyle.cosmeticTypeSymbol(type),
                                           trailing: L("所持 \(owned.count)/\(all.count)", "Owned \(owned.count)/\(all.count)"))
                    LazyVGrid(columns: columns, spacing: 10) {
                        optionCell(preview: AnyView(defaultPreview(type, size: 64)), name: L("デフォルト", "Default"),
                                   state: equipped == nil ? .equipped : .owned, id: "cosmetic_default_\(type.rawValue)") {
                            var p = app.profile
                            CosmeticInfo.unequip(type, profile: &p)
                            app.profile = p
                        }
                        ForEach(owned + locked) { c in
                            cosmeticOption(c)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func defaultPreview(_ type: CosmeticType, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(Theme.panelStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Image(systemName: CollectionStyle.cosmeticTypeSymbol(type))
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: 選択肢

    private enum OptionState {
        case equipped, owned
        case locked(StoreItemDef?)
    }

    private func cosmeticOption(_ c: CosmeticDef) -> some View {
        let owned = app.owns(cosmeticID: c.cosmeticID)
        let equipped = CosmeticInfo.isEquipped(c, profile: app.profile)
        let item = StoreCatalog.storeItem(forCosmetic: c.cosmeticID, master: app.master)
        let state: OptionState = equipped ? .equipped : (owned ? .owned : .locked(item))
        return optionCell(preview: AnyView(CosmeticPreviewView(cosmetic: c, size: 64, animated: false)),
                          name: MasterText.cosmetic(c), state: state, id: "cosmetic_\(c.cosmeticID)") {
            if owned {
                var p = app.profile
                CosmeticInfo.equip(c, profile: &p)
                app.profile = p
            } else if let item {
                app.router.push(.productDetail(item.sku))
            }
        }
    }

    private func optionCell(preview: AnyView, name: String, state: OptionState, id: String, action: @escaping () -> Void) -> some View {
        let isEquipped: Bool = { if case .equipped = state { return true } else { return false } }()
        let isLocked: Bool = { if case .locked = state { return true } else { return false } }()
        return Button {
            app.haptics.tap()
            withAnimation(.spring(duration: 0.25)) { action() }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    preview
                        .saturation(isLocked ? 0.3 : 1)
                        .opacity(isLocked ? 0.6 : 1)
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.7)))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(name)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26)
                Group {
                    switch state {
                    case .equipped:
                        Label(L("装備中", "Equipped"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    case .owned:
                        Text(L("タップで装備", "Tap to equip")).foregroundStyle(Theme.textSecondary)
                    case .locked(let item):
                        if let item {
                            PriceTag(currency: item.currency, amount: EconomyService.price(of: item), size: 10)
                        } else {
                            Text(L("未所持", "Locked")).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .font(Theme.body(9))
                .frame(height: 14)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(isEquipped ? Theme.success.opacity(0.1) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isEquipped ? Theme.success.opacity(0.7) : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(name + (isEquipped ? L("（装備中）", " (equipped)") : (isLocked ? L("（未所持）", " (locked)") : "")))
        .accessibilityIdentifier(id)
    }
}
