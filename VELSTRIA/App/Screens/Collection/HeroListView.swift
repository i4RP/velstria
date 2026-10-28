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
    @State private var sortByName = false

    private let roles: [Role] = [.vanguard, .duelist, .assassin, .arcanist, .ranger, .support]

    var body: some View {
        ScreenScaffold(title: L("ヒーロー", "Heroes")) {
            GeometryReader { geometry in
                let owned = app.profile.ownedHeroIDs
                let filtered = HeroListFilter.heroes(app.master.heroes, role: role, ownership: ownership, owned: owned)
                let heroes = sortByName ? filtered.sorted { MasterText.hero($0) < MasterText.hero($1) } : filtered
                let count = max(3, Int(geometry.size.width / 112))
                let width = max(64, (geometry.size.width - CGFloat(count - 1) * 10) / CGFloat(count))
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                roleButton(nil)
                                ForEach(roles, id: \.self) { roleButton($0) }
                            }
                        }
                        Menu {
                            Picker(L("所持", "Ownership"), selection: $ownership) {
                                ForEach(HeroOwnershipFilter.allCases) { Text($0.title).tag($0) }
                            }
                            Picker(L("並び順", "Sort"), selection: $sortByName) {
                                Text(L("デフォルト", "Default")).tag(false)
                                Text(L("名前順", "Name")).tag(true)
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.cyan)
                                .frame(width: 36, height: 36)
                        }
                        .accessibilityLabel(L("絞り込み・並び順", "Filter and sort"))
                        .accessibilityIdentifier("heroes_owned_filter")
                    }
                    ScrollView {
                        if heroes.isEmpty {
                            EmptyStateView(symbol: "person.2.fill", title: L("該当するヒーローがいません", "No heroes match"),
                                           message: L("フィルターを変更してください", "Try another filter"))
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 10), count: count), spacing: 14) {
                                ForEach(heroes) { hero in
                                    CollectionHeroCard(hero: hero, owned: owned.contains(hero.heroID), width: width)
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .id("\(role?.rawValue ?? "all")-\(ownership)-\(sortByName)")
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func roleButton(_ value: Role?) -> some View {
        CollectionFilterChip(title: value.map { MasterText.role($0) } ?? L("全て", "All"),
                             color: Theme.cyan, isSelected: role == value) {
            app.haptics.tap()
            role = value
        }
        .accessibilityIdentifier("heroes_role_\(value?.rawValue ?? "all")")
    }

}

/// 縦長アートを主役にした一覧カード。画面内のカードだけを遅延生成する。
struct CollectionHeroCard: View {
    let hero: HeroDef
    let owned: Bool
    let width: CGFloat
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.tap()
            app.router.push(.heroDetail(hero.heroID))
        } label: {
            VStack(spacing: 8) {
                Image(systemName: Theme.roleSymbol(hero.role))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                    .padding(.top, 12)
                HeroPortraitView(heroID: hero.heroID, size: max(48, width - 26), showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(owned ? Theme.gold : Theme.cyan.opacity(0.6), lineWidth: 1.5))
                    .saturation(owned ? 1 : 0.45)
                Text(MasterText.hero(hero))
                    .font(Theme.heading(12))
                    .foregroundStyle(owned ? Theme.gold : Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(MasterText.role(hero.role))
                    .font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                if !owned {
                    Label(L("未所持", "Locked"), systemImage: "lock.fill")
                        .font(Theme.body(9)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 5)
            .frame(width: width, height: max(184, width * 1.95))
            .worldShellCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(MasterText.hero(hero))、\(MasterText.role(hero.role))、\(owned ? L("所持", "Owned") : L("未所持", "Locked"))")
        .accessibilityIdentifier("hero_\(hero.heroID)")
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
