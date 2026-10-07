import SwiftUI
import UIKit
import VelstriaCore

// 担当: home-chrome。ホーム画面の見た目の土台（色・フォント・面取り形状・パネル・共通ボタン・光の演出）。
// 方向性: 深い藍の宇宙 + 金（ファンタジー）× シアン / 紫のネオンと面取りパネル（SF）。

// MARK: - 色

enum HomeStyle {
    /// 紫のネオン（#9D6BFF）。
    static let violet = Color(red: 0.616, green: 0.420, blue: 1.0)
    /// エネルギー橙。
    static let ember = Color(red: 1.0, green: 0.55, blue: 0.18)
    /// パネルの地色（暗い藍のガラス）。
    static let ink = Color(red: 0.028, green: 0.043, blue: 0.110)
    static let inkRaised = Color(red: 0.070, green: 0.100, blue: 0.230)
    /// 金の濃淡（飾り線・START）。
    static let goldLight = Color(red: 1.0, green: 0.93, blue: 0.68)
    static let goldDeep = Color(red: 0.78, green: 0.50, blue: 0.15)
    /// 金〜橙の面に載せる文字色。
    static let onGold = Color(red: 0.16, green: 0.08, blue: 0.02)

    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldLight, Theme.gold, goldDeep], startPoint: .top, endPoint: .bottom)
    }

    static func tint(_ mode: HomeMode) -> Color {
        switch mode {
        case .ranked: return Theme.gold
        case .classic: return Theme.cyan
        case .brawl: return ember
        case .arcade: return Theme.success
        case .rising: return Color(red: 1.0, green: 0.46, blue: 0.62)
        case .custom: return Color(red: 0.56, green: 0.70, blue: 1.0)
        case .magicChess: return violet
        }
    }

    static func tint(_ link: HomeQuickLink) -> Color {
        switch link {
        case .missions: return Theme.success
        case .store: return Theme.gold
        case .records: return violet
        }
    }
}

// MARK: - フォント

/// 同梱フォント（App/Resources/Fonts。SIL OFL 1.1）。和文は同梱せず、cascadeList でヒラギノへ落として太さを揃える。
enum HomeFont {
    enum Face: String, CaseIterable {
        case techSemiBold = "ChakraPetch-SemiBold"
        case techBold = "ChakraPetch-Bold"
        case techBoldItalic = "ChakraPetch-BoldItalic"
        case serifBold = "Cinzel-Bold"
        case serifBlack = "Cinzel-Black"

        var isSerif: Bool { self == .serifBold || self == .serifBlack }

        /// 和文の代替（PostScript 名。先頭から、端末にあるものだけを使う）。
        var japaneseFallbacks: [String] {
            switch self {
            case .techSemiBold: return ["HiraginoSans-W6"]
            case .techBold, .techBoldItalic: return ["HiraginoSans-W7", "HiraginoSans-W6"]
            case .serifBold, .serifBlack: return ["HiraMinProN-W6", "HiraginoSans-W6"]
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Font] = [:]

    /// ラベル・数字・英字見出し（Chakra Petch Bold）。
    static func tech(_ size: CGFloat) -> Font { font(.techBold, size: size) }
    /// 補足の小さな文字（Chakra Petch SemiBold）。
    static func label(_ size: CGFloat) -> Font { font(.techSemiBold, size: size) }
    /// 勢いのある見出し（Chakra Petch Bold Italic。和文は斜体にならない）。
    static func italic(_ size: CGFloat) -> Font { font(.techBoldItalic, size: size) }
    /// タイトル的な見出し（Cinzel Bold、和文は明朝）。
    static func serif(_ size: CGFloat) -> Font { font(.serifBold, size: size) }
    /// ヒーロー名などの大見出し（Cinzel Black、和文は明朝）。
    static func display(_ size: CGFloat) -> Font { font(.serifBlack, size: size) }

    static func font(_ face: Face, size: CGFloat) -> Font {
        let key = "\(face.rawValue)@\(size)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let made = Font(uiFont(face, size: size) as CTFont)
        cache[key] = made
        return made
    }

    /// 和文の代替を組み込んだ UIFont。同梱フォントを読めない場合はシステムフォントで代用する。
    static func uiFont(_ face: Face, size: CGFloat) -> UIFont {
        guard UIFont(name: face.rawValue, size: size) != nil else {
            return .systemFont(ofSize: size, weight: face == .techSemiBold ? .semibold : .bold)
        }
        let cascade = face.japaneseFallbacks
            .filter { UIFont(name: $0, size: size) != nil }
            .map { UIFontDescriptor(fontAttributes: [.name: $0]) }
        let descriptor = UIFontDescriptor(fontAttributes: [.name: face.rawValue, .cascadeList: cascade])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// 端末で解決できない同梱フォントの PostScript 名（正常なら空。UIAppFonts の登録漏れの検出用）。
    static var unresolvedFaces: [String] {
        Face.allCases.map(\.rawValue).filter { UIFont(name: $0, size: 12) == nil }
    }
}

/// 等幅に並べた数字。Chakra Petch は等幅数字を持たないので、数字 1 文字ずつを同じ幅の枠に置く（桁区切りや単位は自然な幅）。
struct HomeTabularNumber: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = Theme.textPrimary

    var body: some View {
        let digitWidth = (size * 0.65).rounded(.up)
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .frame(width: character.isNumber ? digitWidth : nil)
            }
        }
        .font(HomeFont.tech(size))
        .foregroundStyle(color)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - 形状

/// 角を斜めに落とした矩形（面取りパネル）。
struct HomeChamfer: InsettableShape {
    struct Corners: OptionSet, Sendable {
        let rawValue: Int
        static let topLeading = Corners(rawValue: 1 << 0)
        static let topTrailing = Corners(rawValue: 1 << 1)
        static let bottomLeading = Corners(rawValue: 1 << 2)
        static let bottomTrailing = Corners(rawValue: 1 << 3)
        /// 左上と右下（既定）。
        static let diagonal: Corners = [.topLeading, .bottomTrailing]
        /// 右上と左下。
        static let antiDiagonal: Corners = [.topTrailing, .bottomLeading]
        static let all: Corners = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
    }

    var cut: CGFloat = 8
    var corners: Corners = .diagonal
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        // 内側へ寄せた分だけ面取りを縮める（45° の辺を平行に保つ: 2 − √2 ≒ 0.586）
        let c = max(0, min(cut - insetAmount * 0.586, min(r.width, r.height) / 2))
        let tl = corners.contains(.topLeading) ? c : 0
        let tr = corners.contains(.topTrailing) ? c : 0
        let bl = corners.contains(.bottomLeading) ? c : 0
        let br = corners.contains(.bottomTrailing) ? c : 0
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + tr))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addLine(to: CGPoint(x: r.maxX - br, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - bl))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> HomeChamfer {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// 面取りした角にだけ引く飾り線（斜辺と、そこから両側の辺へ少し伸ばした鉤形）。
struct HomeChamferAccent: Shape {
    var cut: CGFloat = 8
    var corners: HomeChamfer.Corners = .diagonal
    /// 斜辺の両端から辺に沿って伸ばす長さ。
    var arm: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 0.75, dy: 0.75)
        let c = max(0, min(cut - 0.44, min(r.width, r.height) / 2))
        let a = min(arm, max(0, min(r.width, r.height) / 2 - c))
        var p = Path()
        if corners.contains(.topLeading) {
            p.move(to: CGPoint(x: r.minX, y: r.minY + c + a))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + c + a, y: r.minY))
        }
        if corners.contains(.topTrailing) {
            p.move(to: CGPoint(x: r.maxX - c - a, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c + a))
        }
        if corners.contains(.bottomTrailing) {
            p.move(to: CGPoint(x: r.maxX, y: r.maxY - c - a))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX - c - a, y: r.maxY))
        }
        if corners.contains(.bottomLeading) {
            p.move(to: CGPoint(x: r.minX + c + a, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c - a))
        }
        return p
    }
}

/// 右レールの折りたたみ取っ手（右辺がレールに接する台形）。
struct HomeHandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let slant = min(rect.height * 0.22, rect.width)
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - slant))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + slant))
        p.closeSubpath()
        return p
    }
}

/// 菱形（飾り）。
struct HomeDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - パネル

/// 面取りパネル（暗い藍のガラス + ネオンの縁 + 面取り角の金の飾り線）。
struct HomePanel: ViewModifier {
    var cut: CGFloat = 8
    var corners: HomeChamfer.Corners = .diagonal
    var tint: Color = Theme.cyan
    /// 地のガラスの不透明度。
    var opacity: Double = 0.74
    /// 選択・強調（縁が発光する）。
    var highlighted = false
    /// 面取り角の金の飾り線を付けるか。
    var accent = true

    func body(content: Content) -> some View {
        let shape = HomeChamfer(cut: cut, corners: corners)
        content
            .background {
                shape.fill(LinearGradient(colors: [HomeStyle.inkRaised.opacity(opacity), HomeStyle.ink.opacity(opacity)],
                                          startPoint: .top, endPoint: .bottom))
                shape.fill(LinearGradient(colors: [tint.opacity(highlighted ? 0.30 : 0.14), .clear],
                                          startPoint: .topLeading, endPoint: UnitPoint(x: 0.7, y: 1)))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [tint.opacity(highlighted ? 1 : 0.85), tint.opacity(highlighted ? 0.45 : 0.14)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: highlighted ? 1.5 : 1)
                    .shadow(color: tint.opacity(highlighted ? 0.7 : 0), radius: 5)
                    .allowsHitTesting(false)
            }
            .overlay {
                if accent {
                    HomeChamferAccent(cut: cut, corners: corners)
                        .stroke(Theme.gold.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func homePanel(cut: CGFloat = 8, corners: HomeChamfer.Corners = .diagonal, tint: Color = Theme.cyan,
                   opacity: Double = 0.74, highlighted: Bool = false, accent: Bool = true) -> some View {
        modifier(HomePanel(cut: cut, corners: corners, tint: tint, opacity: opacity, highlighted: highlighted, accent: accent))
    }

    /// 全画面座標の矩形に置く（HomeMetrics の矩形用）。
    func homePlaced(in rect: CGRect) -> some View {
        frame(width: max(0, rect.width), height: max(0, rect.height))
            .position(x: rect.midX, y: rect.midY)
    }
}

/// 帯（ヘッダー・フッター）の地。画面端まで敷き、内側の辺に光る線を引く。
struct HomeBandBackground: View {
    enum Side { case top, bottom }
    /// 帯が付いている画面の辺。
    let side: Side

    var body: some View {
        let outer: UnitPoint = side == .top ? .top : .bottom
        let inner: UnitPoint = side == .top ? .bottom : .top
        ZStack(alignment: side == .top ? .bottom : .top) {
            LinearGradient(colors: [HomeStyle.ink.opacity(0.96), HomeStyle.ink.opacity(0.78)], startPoint: outer, endPoint: inner)
            LinearGradient(colors: [HomeStyle.inkRaised.opacity(0.0), HomeStyle.inkRaised.opacity(0.55)], startPoint: outer, endPoint: inner)
            // 帯の外へ落ちる影（背景のアートとなじませる）
            LinearGradient(colors: [Color.black.opacity(0.35), .clear], startPoint: outer, endPoint: inner)
                .frame(height: 10)
                .offset(y: side == .top ? 10 : -10)
            HomeEdgeLine()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// 帯の縁の線（両端へ消えるシアン + 中央の金）。
struct HomeEdgeLine: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [Theme.cyan.opacity(0), Theme.cyan.opacity(0.9), Theme.gold, Theme.cyan.opacity(0.9), Theme.cyan.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .shadow(color: Theme.cyan.opacity(0.9), radius: 3)
            HomeDiamond()
                .fill(HomeStyle.goldLight)
                .frame(width: 7, height: 7)
                .shadow(color: Theme.gold, radius: 3)
        }
        .frame(height: 7)
        .offset(y: 3)
    }
}

// MARK: - ボタン

/// 押下時の反応（縮む + 明るくなる）。
struct HomePressStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.16 : 0)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

/// 記号を載せた面取りタイル（リスト項目・ドロワー項目のアイコン）。
struct HomeGlyphTile: View {
    let symbol: String
    var tint: Color = Theme.cyan
    var size: CGFloat = 38

    var body: some View {
        let shape = HomeChamfer(cut: size * 0.22)
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: tint, radius: 4)
            .frame(width: size, height: size)
            .background {
                shape.fill(HomeStyle.ink.opacity(0.7))
                shape.fill(LinearGradient(colors: [tint.opacity(0.62), tint.opacity(0.16)], startPoint: .top, endPoint: .bottom))
            }
            .overlay { shape.strokeBorder(LinearGradient(colors: [tint, tint.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// ヘッダーのアイコンボタン（表示 40pt・当たり判定 44pt）。
struct HomeIconButton: View {
    let symbol: String
    let label: String
    var badge = 0
    var tint: Color = Theme.cyan
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .homePanel(cut: 8, tint: tint, opacity: 0.8, accent: false)
                .overlay(alignment: .topTrailing) { FlowCountBadge(count: badge).offset(x: 5, y: -3) }
                .frame(width: HomeMetrics.minTapSize, height: HomeMetrics.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.9))
        .accessibilityLabel(badge > 0 ? "\(label) \(L("未読", "unread")) \(badge)" : label)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - 光の演出

/// 斜めの光沢が左から右へ走る（待ち → 走る を繰り返す）。
/// 止める手段を持たないので、ホームが前面の間だけ階層に入れること（`if animated { HomeSheen() }`）。
struct HomeSheen: View {
    /// 1 周の秒数（うち 3 割が走る時間）。
    var period: Double = 4
    var tint: Color = .white
    @State private var swept = false

    var body: some View {
        GeometryReader { geo in
            let band = max(22, geo.size.width * 0.2)
            LinearGradient(colors: [.clear, tint.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: band, height: geo.size.height * 2.4)
                .rotationEffect(.degrees(22))
                .offset(x: swept ? geo.size.width + band : -band * 2, y: -geo.size.height * 0.7)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: period * 0.3).delay(period * 0.7).repeatForever(autoreverses: false)) {
                swept = true
            }
        }
    }
}

/// 形の背後でゆっくり明滅する発光。animated が偽の間は一定の明るさで止まる。
struct HomeGlow<S: Shape>: View {
    let shape: S
    var color: Color
    var radius: CGFloat = 12
    var animated: Bool

    var body: some View {
        Group {
            if animated {
                HomeGlowPulse(shape: shape, color: color, radius: radius)
            } else {
                shape.fill(color).blur(radius: radius).opacity(0.6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HomeGlowPulse<S: Shape>: View {
    let shape: S
    let color: Color
    let radius: CGFloat
    @State private var bright = false

    var body: some View {
        shape.fill(color)
            .blur(radius: radius)
            .opacity(bright ? 0.95 : 0.4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}
