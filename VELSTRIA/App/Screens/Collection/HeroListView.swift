import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI037 ヒーロー一覧。

enum HeroOwnershipFilter: CaseIterable, Identifiable {
    case all, owned, locked
    var id: Self { self }

    var title: String {
        switch self {
        case .all: return L("すべて", "All")
        case .owned: return L("所持", "Owned")
        case .locked: return L("未所持", "Locked")
        }
    }
}

enum HeroListFilter {
    static func heroes(_ heroes: [HeroDef], role: Role?, ownership: HeroOwnershipFilter, owned: [String]) -> [HeroDef] {
        heroes.filter { h in
            guard role == nil || h.role == role else { return false }
            switch ownership {
            case .all: return true
            case .owned: return owned.contains(h.heroID)
            case .locked: return !owned.contains(h.heroID)
            }
        }
    }
}

struct HeroListView: View {
    @Environment(AppModel.self) private var app
    @State private var role: Role?
    @State private var ownership: HeroOwnershipFilter = .all

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 10)]

    var body: some View {
        let owned = app.profile.ownedHeroIDs
        let heroes = HeroListFilter.heroes(app.master.heroes, role: role, ownership: ownership, owned: owned)
        ScreenScaffold(title: L("ヒーロー", "Heroes")) {
            VStack(spacing: 4) {
                filterBar(ownedCount: app.master.heroes.filter { owned.contains($0.heroID) }.count)
                ScrollView {
                    if heroes.isEmpty {
                        CollectionEmptyState(symbol: "person.2.fill",
                                             title: L("該当するヒーローがいません", "No heroes match"),
                                             message: L("フィルターを変更してください", "Try another filter"))
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(heroes) { h in
                                CollectionHeroCard(hero: h, owned: owned.contains(h.heroID))
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
                .scrollIndicators(.hidden)
                .animation(.spring(duration: 0.35), value: role)
                .animation(.spring(duration: 0.35), value: ownership)
            }
        }
    }

    private func filterBar(ownedCount: Int) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    CollectionFilterChip(title: L("全ロール", "All Roles"), symbol: "square.grid.2x2.fill",
                                         color: Theme.cyan, isSelected: role == nil) { role = nil }
                        .accessibilityIdentifier("heroes_role_all")
                    ForEach(Role.allCases, id: \.self) { r in
                        CollectionFilterChip(title: MasterText.role(r), symbol: Theme.roleSymbol(r),
                                             color: Theme.roleColor(r), isSelected: role == r, showsTitle: false) {
                            role = role == r ? nil : r
                        }
                        .accessibilityIdentifier("heroes_role_\(r.rawValue)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            Picker(L("所持", "Ownership"), selection: $ownership) {
                ForEach(HeroOwnershipFilter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .accessibilityIdentifier("heroes_owned_filter")
            Text("\(ownedCount)/\(app.master.heroes.count)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(L("所持 \(ownedCount) / \(app.master.heroes.count)", "Owned \(ownedCount) of \(app.master.heroes.count)"))
        }
        .padding(.horizontal, 20)
    }
}

/// 一覧のヒーローカード。
struct CollectionHeroCard: View {
    let hero: HeroDef
    let owned: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.tap()
            app.router.push(.heroDetail(hero.heroID))
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    HeroPortraitView(heroID: hero.heroID, size: 70)
                        .saturation(owned ? 1 : 0.35)
                        .opacity(owned ? 1 : 0.75)
                    if owned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.success)
                            .background(Circle().fill(Color.black.opacity(0.6)).padding(1))
                            .offset(x: 6, y: -6)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .overlay(Circle().stroke(Theme.gold.opacity(0.7), lineWidth: 1))
                            .offset(x: 6, y: -6)
                    }
                }
                .padding(.top, 4)
                Text(MasterText.hero(hero))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .frame(height: 32)
                HStack(spacing: 4) {
                    CollectionRoleTag(role: hero.role, compact: true)
                    CollectionDifficultyStars(value: hero.difficulty, size: 8)
                }
                ownershipLine
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.roleColor(hero.role).opacity(0.16), Theme.panel],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(owned ? Theme.roleColor(hero.role).opacity(0.55) : Theme.panelStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(MasterText.hero(hero))、\(MasterText.role(hero.role))、\(owned ? L("所持", "Owned") : L("未所持", "Locked"))")
        .accessibilityIdentifier("hero_\(hero.heroID)")
    }

    @ViewBuilder
    private var ownershipLine: some View {
        if owned {
            Text(L("所持", "Owned"))
                .font(Theme.body(11))
                .foregroundStyle(Theme.success)
        } else if let item = StoreCatalog.unlockItem(heroID: hero.heroID, master: app.master) {
            PriceTag(currency: item.currency, amount: EconomyService.price(of: item), size: 11)
        } else {
            Text(L("未所持", "Locked"))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// 押下時に少し縮むカード用スタイル。
struct CollectionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
