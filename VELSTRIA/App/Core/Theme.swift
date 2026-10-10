import SwiftUI
import VelstriaCore

// 担当: 統合（契約）。Wave 1 では読み取り専用。追加の共通部品は各担当フォルダに作ること。

enum Theme {
    // 背景: 深い藍 → 紫の星空
    static let bgTop = Color(red: 0.04, green: 0.05, blue: 0.13)
    static let bgBottom = Color(red: 0.10, green: 0.06, blue: 0.20)
    static let panel = Color(red: 0.09, green: 0.10, blue: 0.20).opacity(0.92)
    static let panelStroke = Color(red: 0.55, green: 0.62, blue: 0.95).opacity(0.35)
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

/// 画面全体の背景（星空グラデーション）。
struct StarfieldBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var rng = SplitMix64(seed: 2026)
                for _ in 0..<120 {
                    let x = rng.nextDouble() * size.width
                    let y = rng.nextDouble() * size.height
                    let r = 0.4 + rng.nextDouble() * 1.4
                    let a = 0.25 + rng.nextDouble() * 0.6
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(a)))
                }
            }
            RadialGradient(colors: [Theme.cyan.opacity(0.10), .clear], center: .init(x: 0.8, y: 0.2),
                           startRadius: 10, endRadius: 500)
        }
        .ignoresSafeArea()
    }
}

/// 標準パネル。
struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
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
                Capsule().fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: color.opacity(0.45), radius: configuration.isPressed ? 2 : 8)
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
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10)))
            .overlay(Capsule().stroke(Theme.panelStroke, lineWidth: 1))
    }
}

/// 通貨表示。
struct CurrencyBadge: View {
    enum Kind { case coin, gem }
    let kind: Kind
    let amount: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind == .coin ? "star.circle.fill" : "diamond.fill")
                .foregroundStyle(kind == .coin ? Theme.gold : Theme.cyan)
            Text(amount.formatted())
                .font(Theme.mono(14))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

/// push 画面の共通レイアウト（背景・タイトル・戻る）。
struct ScreenScaffold<Content: View>: View {
    let title: String
    var showsCurrencies = true
    @ViewBuilder var content: () -> Content
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        app.router.pop()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel(L("戻る", "Back"))
                    .accessibilityIdentifier("nav_back")
                    Text(title)
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if showsCurrencies {
                        CurrencyBadge(kind: .coin, amount: app.profile.starlightCoin)
                        CurrencyBadge(kind: .gem, amount: app.profile.totalGem)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 描き下ろしアート（Assets.xcassets の HeroPortraits / SkinPortraits / ItemIcons）。
/// 生成元は tools/portraits/（仕様 portraits.json・item_icons.json、取り込み portraits.py install）。
enum PortraitArt {
    @MainActor private static var cache: [String: UIImage?] = [:]

    @MainActor static func hero(_ heroID: String) -> UIImage? { image("HeroPortraits/\(heroID)") }

    @MainActor static func skin(_ cosmeticID: String) -> UIImage? { image("SkinPortraits/\(cosmeticID)") }

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
    @Environment(AppModel.self) private var app

    var body: some View {
        let def = app.master.hero(heroID)
        let hue = Theme.heroHue(heroID)
        ZStack {
            if let art = PortraitArt.hero(heroID) {
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
