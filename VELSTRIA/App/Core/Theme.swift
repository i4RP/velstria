import SwiftUI
import VelstriaCore

/// 非バトル画面は、ルートの同じ背景と固定ヘッダーの中に描画する。
private struct WorldShellEmbeddedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isWorldShellEmbedded: Bool {
        get { self[WorldShellEmbeddedKey.self] }
        set { self[WorldShellEmbeddedKey.self] = newValue }
    }
}

enum Theme {
    // パーティロビーをすべての画面に共通する世界とする。
    static let bgTop = Color(red: 0.06, green: 0.20, blue: 0.48)
    static let bgBottom = Color(red: 0.12, green: 0.42, blue: 0.78)
    static let panel = Color(red: 0.10, green: 0.29, blue: 0.58).opacity(0.55)
    static let panelStroke = Color(red: 0.40, green: 0.88, blue: 1.00).opacity(0.42)
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.38)
    static let cyan = Color(red: 0.40, green: 0.88, blue: 1.00)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let success = Color(red: 0.36, green: 0.92, blue: 0.62)

    static func teamColor(_ team: Team, colorblind: Bool = false) -> Color {
        switch team {
        case .blue: return colorblind ? Color(red: 0.25, green: 0.55, blue: 1.0) : Color(red: 0.28, green: 0.62, blue: 1.0)
        case .red: return colorblind ? Color(red: 1.0, green: 0.62, blue: 0.15) : Color(red: 1.0, green: 0.32, blue: 0.36)
        case .neutral: return Color(red: 0.85, green: 0.80, blue: 0.55)
        }
    }

    static func rarityColor(_ r: Rarity) -> Color {
        switch r {
        case .common: return Color(red: 0.70, green: 0.76, blue: 0.84)
        case .rare: return Color(red: 0.35, green: 0.66, blue: 1.0)
        case .epic: return Color(red: 0.72, green: 0.42, blue: 1.0)
        case .mythic: return Color(red: 1.0, green: 0.62, blue: 0.22)
        }
    }

    static func roleColor(_ r: Role) -> Color {
        switch r {
        case .vanguard: return Color(red: 0.45, green: 0.72, blue: 0.95)
        case .duelist: return Color(red: 0.95, green: 0.55, blue: 0.35)
        case .ranger: return Color(red: 0.55, green: 0.90, blue: 0.45)
        case .arcanist: return Color(red: 0.72, green: 0.52, blue: 1.0)
        case .support: return Color(red: 0.40, green: 0.92, blue: 0.82)
        case .assassin: return Color(red: 0.95, green: 0.38, blue: 0.62)
        }
    }

    /// 色だけに依存しない識別のためのロール記号（SF Symbols）。
    static func roleSymbol(_ r: Role) -> String {
        switch r {
        case .vanguard: return "shield.lefthalf.filled"
        case .duelist: return "figure.fencing"
        case .ranger: return "scope"
        case .arcanist: return "sparkles"
        case .support: return "cross.circle.fill"
        case .assassin: return "moon.stars.fill"
        }
    }

    /// 造形設計の配色（NEW_HEROES.md）に合わせて、番号から決まる色相を上書きするヒーロー。
    private static let heroHueOverrides: [String: Double] = [
        "H025": 0.66,  // ルミナ: 青紫（銀は HeroBlueprints の metal、外套の青は accent）
        "H026": 0.62,  // エウリア: 青（全身衣。白い外套は cloth、電光の青紫は glow）
        "H027": 0.50,  // ジャルド: 青緑の鎧（淡い上衣は cloth、金は metal、赤は accent）
        "H028": 0.59,  // ザイル: 鋼青（黒い下地は dark、銀は metal、赤い visor・襟巻きは glow・accent）
        "H029": 0.60,  // ボルグ: 青（金は HeroBlueprints の metal、赤は accent）
        "H030": 0.63,  // ライナ: 青（スカート・紺のネクタイ。白い上着は cloth、金は metal、茶革は accent）
        "H031": 0.645, // オーリア: 群青のドレス（銀青の袖は cloth、氷の水色は accent）
        "H032": 0.71,  // ディアス: 濃い紫の鎧（secondary。金の刃の輪は metal、紅は accent・glow）
        "H033": 0.61,  // ヴァルド: 青（濃紺のコートは secondary、銀の大剣は metal、銅の縁は accent）
        "H034": 0.08,  // ゴルム: 鉄茶
    ]

    /// ヒーロー固有の色相（ポートレート・3D モデルの基調色）。
    static func heroHue(_ heroID: String) -> Double {
        if let h = heroHueOverrides[heroID] { return h }
        let n = Double(Int(heroID.dropFirst()) ?? 0)
        return (n * 0.137).truncatingRemainder(dividingBy: 1.0)
    }

    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func heading(_ size: CGFloat = 18) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func body(_ size: CGFloat = 14) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    static func mono(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
}

/// 旧画面もルートと同じ背景を共有する。
struct StarfieldBackground: View {
    @Environment(\.isWorldShellEmbedded) private var isEmbedded

    var body: some View {
        Group {
            if isEmbedded {
                Color.clear
            } else {
                PartyBackdrop()
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// パーティの席と同じ、青い透過面・細いシアンの上辺・菱形。
struct WorldCardSurface: View {
    var tint: Color = Theme.cyan
    var selected = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Theme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(selected ? Theme.gold : tint.opacity(0.35), lineWidth: selected ? 1.5 : 1)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(tint.opacity(0.85)).frame(height: 2)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(tint).frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45)).offset(y: -3)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func worldShellCard(selected: Bool = false) -> some View {
        background(WorldCardSurface(selected: selected))
    }
}

/// 標準パネル。
struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .worldShellCard()
    }
}

/// 主要ボタン。
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.gold

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.heading(16))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(
                PartyBannerShape().fill(LinearGradient(colors: [color.opacity(0.95), color], startPoint: .top, endPoint: .bottom))
            )
            .overlay(PartyBannerShape().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 2 : 6)
    }
}

/// 副ボタン。
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.heading(15))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bgTop.opacity(configuration.isPressed ? 0.85 : 0.65)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.cyan.opacity(0.6), lineWidth: 1))
    }
}

/// 通貨表示。
struct CurrencyBadge: View {
    enum Kind { case coin, gem }
    let kind: Kind
    let amount: Int

    var body: some View {
        HStack(spacing: 5) {
            CurrencyIcon(kind: kind == .coin ? .coin : .gem, size: 16)
            Text(amount.formatted())
                .font(Theme.heading(13))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bgTop.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.panelStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// push 画面の共通レイアウト（背景・タイトル・戻る）。
struct ScreenScaffold<Content: View>: View {
    let title: String
    var showsCurrencies = true
    @ViewBuilder var content: () -> Content
    @Environment(AppModel.self) private var app
    @Environment(\.isWorldShellEmbedded) private var isEmbedded

    var body: some View {
        Group {
            if isEmbedded {
                content()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                ZStack {
                    CelestialBackdrop()
                    VStack(spacing: 0) {
                        standaloneHeader
                        content()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var standaloneHeader: some View {
        HStack(spacing: 12) {
            Button { app.router.pop() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 22, weight: .heavy))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Theme.gold)
            .accessibilityLabel(L("戻る", "Back"))
            .accessibilityIdentifier("nav_back")
            Text(title)
                .font(Theme.title(22))
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            if showsCurrencies {
                CurrencyBadge(kind: .coin, amount: app.profile.starlightCoin)
                CurrencyBadge(kind: .gem, amount: app.profile.totalGem)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .zIndex(1)
    }
}

/// 描き下ろしアート（Assets.xcassets の HeroPortraits / SkinPortraits / ItemIcons）。
/// 生成元は tools/portraits/（仕様 portraits.json・item_icons.json、取り込み portraits.py install）。
enum PortraitArt {
    @MainActor private static var cache: [String: UIImage?] = [:]

    @MainActor static func hero(_ heroID: String) -> UIImage? { image("HeroPortraits/\(heroID)") }

    @MainActor static func skin(_ cosmeticID: String) -> UIImage? { image("SkinPortraits/\(cosmeticID)") }

    /// 顔だけに寄せたアイコン（HeroFaces。ロード画面のカード絵 HeroCards から切り抜き。tools/portraits/cards.py）。
    @MainActor static func face(_ heroID: String) -> UIImage? { image("HeroFaces/\(heroID)") }

    /// ロード画面のカード絵（縦長 2:3。HeroCards）。
    @MainActor static func card(_ heroID: String) -> UIImage? { image("HeroCards/\(heroID)") }

    /// 装備アイコン（Assets.xcassets の ItemIcons。仕様は tools/portraits/item_icons.json）。
    @MainActor static func item(_ itemID: String) -> UIImage? { image("ItemIcons/\(itemID)") }

    /// バトルスペルの描き下ろしアイコン（Assets.xcassets の SpellIcons。無ければ手続き生成へフォールバック）。
    @MainActor static func spell(_ spellID: String) -> UIImage? { image("SpellIcons/\(spellID)") }

    /// UI 装飾アート（スコアボードの枠・地色・チーム幕など。Assets.xcassets の UIFrames。
    /// 仕様は tools/portraits/ui_frames.json。無ければコードの手続き描画へフォールバック）。
    @MainActor static func frame(_ name: String) -> UIImage? { image("UIFrames/\(name)") }

    @MainActor private static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        let img = UIImage(named: name)
        cache[name] = img
        return img
    }
}

/// ヒーローポートレート（描き下ろしアート。アートの無い ID は色面 + 頭文字の暫定表示）。
struct HeroPortraitView: View {
    let heroID: String
    var size: CGFloat = 64
    var showsRole = true
    /// 顔に寄せたアイコン（HeroFaces）を優先する（HUD の小さな枠用）。
    var face = false
    @Environment(AppModel.self) private var app

    var body: some View {
        let def = app.master.hero(heroID)
        let hue = Theme.heroHue(heroID)
        ZStack {
            if let art = (face ? PortraitArt.face(heroID) : nil) ?? PortraitArt.hero(heroID) {
                Image(uiImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.65, brightness: 0.85),
                                                  Color(hue: hue, saturation: 0.8, brightness: 0.30)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(def?.codeName.prefix(1) ?? "?"))
                    .font(.system(size: size * 0.5, weight: .black, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.4), radius: 3)
            }
            if showsRole, let role = def?.role {
                Image(systemName: Theme.roleSymbol(role))
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(size * 0.06)
                    .background(Circle().fill(Theme.roleColor(role)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
        .accessibilityLabel(def.map { MasterText.hero($0) } ?? heroID)
    }
}

/// 未実装画面の暫定表示（Wave 1 で全て置き換えられる）。
struct PlaceholderScreen: View {
    let title: String
    let screenID: String

    var body: some View {
        ScreenScaffold(title: title) {
            Text("\(screenID) — \(title)")
                .font(Theme.heading())
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
