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

    private let blue = Color(red: 0.57, green: 0.84, blue: 1)
    private let roles: [Role] = [.vanguard, .duelist, .assassin, .arcanist, .ranger, .support]

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = min(170, geometry.size.width * 0.19)
            let columnCount = geometry.size.width > 600 ? 5 : 3
            let gridWidth = max(100, geometry.size.width - sidebarWidth - 48)
            let cardWidth = max(20, (gridWidth - 6 - CGFloat(columnCount - 1) * 20) / CGFloat(columnCount))
            let owned = app.profile.ownedHeroIDs
            let filtered = HeroListFilter.heroes(app.master.heroes, role: role, ownership: ownership, owned: owned)
            let heroes = sortByName ? filtered.sorted { MasterText.hero($0) < MasterText.hero($1) } : filtered
            ZStack {
                GeometryReader { background in
                    Image("HeroRosterBackdrop")
                        .resizable()
                        .scaledToFill()
                        .frame(width: background.size.width, height: background.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                Color(red: 0.12, green: 0.23, blue: 0.43).opacity(0.3).ignoresSafeArea()
                VStack(spacing: 0) {
                    header(sidebarWidth: sidebarWidth)
                    HStack(alignment: .top, spacing: 24) {
                        ScrollView {
                            VStack(spacing: 3) {
                                roleButton(nil)
                                ForEach(roles, id: \.self) { roleButton($0) }
                            }
                            .padding(.top, 8)
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: sidebarWidth)
                        ScrollView {
                            if heroes.isEmpty {
                                EmptyStateView(symbol: "person.2.fill",
                                                     title: L("該当するヒーローがいません", "No heroes match"),
                                                     message: L("フィルターを変更してください", "Try another filter"))
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columnCount), spacing: 18) {
                                    ForEach(heroes) { hero in
                                        CollectionHeroCard(hero: hero, owned: owned.contains(hero.heroID), width: cardWidth)
                                    }
                                }
                                .padding(.top, 10)
                                .padding(.bottom, 20)
                                .padding(.horizontal, 3)
                            }
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: gridWidth)
                        .id("\(role?.rawValue ?? "all")-\(ownership)-\(sortByName)")
                    }
                    .padding(.trailing, 24)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func header(sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 14) {
            Button { app.router.pop() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(blue)
                    .shadow(color: blue, radius: 5)
                    .frame(width: sidebarWidth, height: 44)
                    .background(Color(red: 0.08, green: 0.16, blue: 0.31).opacity(0.65))
            }
            .accessibilityLabel(L("戻る", "Back"))
            .accessibilityIdentifier("nav_back")
            Text(L("ヒーロー", "Heroes"))
                .font(Theme.title(17))
                .foregroundStyle(blue)
            Spacer(minLength: 0)
            Menu {
                Picker(L("所持", "Ownership"), selection: $ownership) {
                    ForEach(HeroOwnershipFilter.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                menuLabel(ownership.title)
            }
            .accessibilityIdentifier("heroes_owned_filter")
            Menu {
                Picker(L("並び順", "Sort"), selection: $sortByName) {
                    Text(L("デフォルト", "Default")).tag(false)
                    Text(L("名前順", "Name")).tag(true)
                }
            } label: {
                menuLabel(sortByName ? L("名前順", "Name") : L("デフォルト", "Default"))
            }
            .accessibilityIdentifier("heroes_sort")
        }
        .padding(.trailing, 24)
        .padding(.bottom, 8)
        .background(Color(red: 0.15, green: 0.24, blue: 0.43).opacity(0.45))
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 16) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down")
        }
        .font(Theme.body(12))
        .foregroundStyle(blue)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(red: 0.1, green: 0.2, blue: 0.37).opacity(0.7))
        .overlay(Rectangle().stroke(blue.opacity(0.3), lineWidth: 1))
    }

    private func roleButton(_ value: Role?) -> some View {
        let selected = role == value
        return Button {
            app.haptics.tap()
            role = value
        } label: {
            Text(value.map { MasterText.role($0) } ?? L("全て", "All"))
                .font(Theme.title(15))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color(red: 0.1, green: 0.25, blue: 0.42) : blue)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if selected {
                        HeroCategoryShape()
                            .fill(LinearGradient(colors: [blue.opacity(0.2), Color.cyan.opacity(0.8), blue], startPoint: .leading, endPoint: .trailing))
                            .overlay(HeroCategoryShape().stroke(blue, lineWidth: 1.5))
                            .shadow(color: .cyan.opacity(0.6), radius: 5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("heroes_role_\(value?.rawValue ?? "all")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HeroCategoryShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: rect.maxX - 14, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 14, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.closeSubpath()
        }
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
            Color.clear
                .frame(width: width, height: width / 0.58)
                .overlay {
                    GeometryReader { geometry in
                        if let art = PortraitArt.card(hero.heroID) ?? PortraitArt.hero(hero.heroID) {
                            Image(uiImage: art)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .saturation(owned ? 1 : 0.45)
                        } else {
                            HeroPortraitView(heroID: hero.heroID, size: geometry.size.width, showsRole: false)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: Theme.roleSymbol(hero.role))
                                .foregroundStyle(Theme.gold)
                            Spacer()
                            if !owned {
                                Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .font(.system(size: 12))
                        Text(MasterText.hero(hero))
                            .font(Theme.body(11))
                            .foregroundStyle(Color(red: 0.55, green: 0.9, blue: 1))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                    .padding(.top, 28)
                    .background(LinearGradient(colors: [.clear, Color(red: 0.04, green: 0.10, blue: 0.25).opacity(0.96)], startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.40, green: 0.65, blue: 0.87).opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
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
