import SwiftUI
import VelstriaCore

// 担当: battle-hud。戦闘 HUD の共通スタイルと画面配置（横画面・左利き反転・Safe Area 対応）。

enum HUDStyle {
    static let glassTop = Color(red: 0.10, green: 0.12, blue: 0.24).opacity(0.78)
    static let glassBottom = Color(red: 0.03, green: 0.04, blue: 0.10).opacity(0.86)
    static let rim = Color(red: 0.62, green: 0.70, blue: 1.0).opacity(0.45)
    static let hp = Color(red: 0.30, green: 0.92, blue: 0.48)
    static let hpLow = Color(red: 1.0, green: 0.30, blue: 0.32)
    static let mana = Color(red: 0.32, green: 0.62, blue: 1.0)
    static let energy = Color(red: 1.0, green: 0.86, blue: 0.30)
    static let xp = Color(red: 0.62, green: 0.48, blue: 1.0)
    static let shield = Color.white.opacity(0.88)

    static func number(_ v: Double) -> String { String(Int(max(0, v).rounded())) }

    /// mm:ss（1 時間以上は h:mm:ss）。
    static func clock(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60) }
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    /// クールダウン表示（10 秒未満は小数 1 桁）。
    static func cooldown(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", max(0.1, v)) : String(Int(v.rounded(.up)))
    }

    static func resourceColor(_ kind: ResourceKind) -> Color { kind == .energy ? energy : mana }
}

/// 半透明ガラス調の面。
struct HUDGlass: ViewModifier {
    var cornerRadius: CGFloat = 12
    var tint: Color = HUDStyle.rim

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [tint, tint.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1)
            )
    }
}

extension View {
    func hudGlass(cornerRadius: CGFloat = 12, tint: Color = HUDStyle.rim) -> some View {
        modifier(HUDGlass(cornerRadius: cornerRadius, tint: tint))
    }

    /// タップ可能な HUD 部品の共通アクセシビリティ設定。
    func hudAccessibility(id: String, label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
            .accessibilityAction(.default, action)
    }
}

/// Gold の硬貨アイコン。
struct HUDCoin: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.55), Color(red: 0.85, green: 0.58, blue: 0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color(red: 0.55, green: 0.35, blue: 0.05).opacity(0.8), lineWidth: max(0.8, size * 0.08))
                .padding(size * 0.16)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.38, weight: .black))
                .foregroundStyle(Color(red: 0.62, green: 0.40, blue: 0.06).opacity(0.85))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 上部の丸いアイコンボタン（44pt）。
struct HUDRoundButton: View {
    let symbol: String
    let label: String
    let identifier: String
    var size: CGFloat = 44
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom],
                                                         startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(HUDStyle.rim, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// 押下時に少し縮む。
struct HUDPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

/// チュートリアルで操作を示す脈動リング。
struct HUDHighlightRing: View {
    var diameter: CGFloat
    @State private var on = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.gold, lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .scaleEffect(on ? 1.18 : 0.96)
            .opacity(on ? 0.25 : 1)
            .shadow(color: Theme.gold.opacity(0.9), radius: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - 配置

/// 画面サイズと Safe Area から各操作部品の位置を決める（座標は HUD 全面のローカル座標）。
/// 右手配置で計算し、左利き配置では x を左右反転する。
struct HUDLayout: Equatable {
    let size: CGSize
    let safe: EdgeInsets
    let leftHanded: Bool
    /// iPhone 16e 横（844×390）を 1.0 とする倍率。
    let scale: CGFloat

    init(size: CGSize, safe: EdgeInsets, leftHanded: Bool) {
        self.size = size
        self.safe = safe
        self.leftHanded = leftHanded
        let s = min(size.height / 390, size.width / 844)
        scale = min(1.18, max(0.84, s))
    }

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    /// 左右の Safe Area（Dynamic Island / ノッチ側）。横画面では左右対称。
    var leadingEdge: CGFloat { max(safe.leading, 10) }
    var trailingEdge: CGFloat { size.width - max(safe.trailing, 10) }
    /// ホームインジケータの上端。
    var bottomEdge: CGFloat { size.height - max(safe.bottom, 8) }
    var topEdge: CGFloat { max(safe.top, 6) }

    /// 右手配置の x を現在の配置へ。
    func mx(_ x: CGFloat) -> CGFloat { leftHanded ? size.width - x : x }

    // MARK: 右側クラスタ（攻撃・スキル・スペル・帰還）

    var attackDiameter: CGFloat { 86 * scale }
    func attackDiameter(for slot: AttackButtonSlot) -> CGFloat {
        slot == .center ? attackDiameter : 54 * scale
    }
    var skillDiameter: CGFloat { 60 * scale }
    var ultDiameter: CGFloat { 66 * scale }
    var spellDiameter: CGFloat { 50 * scale }
    var recallDiameter: CGFloat { max(44, 46 * scale) }
    var levelBadgeDiameter: CGFloat { 30 * scale }

    private var attackCenterRight: CGPoint {
        CGPoint(x: trailingEdge - 8 * scale - attackDiameter / 2, y: bottomEdge - 121 * scale)
    }

    var attackCenter: CGPoint { mirrored(attackCenterRight) }

    /// 上下の優先攻撃ボタンは中央の大きなボタンと縦に並べる。
    func attackCenter(for slot: AttackButtonSlot) -> CGPoint {
        switch slot {
        case .top: return actionPoint(x: 0, y: -74)
        case .center: return attackCenter
        case .bottom: return actionPoint(x: 0, y: 74)
        }
    }

    /// 中央攻撃ボタンからの位置。スキル群は攻撃列の内側へ配置する。
    private func actionPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        let c = attackCenterRight
        return mirrored(CGPoint(x: c.x + x * scale, y: c.y + y * scale))
    }

    private func mirrored(_ p: CGPoint) -> CGPoint { CGPoint(x: mx(p.x), y: p.y) }

    func skillCenter(_ slot: SkillSlot) -> CGPoint {
        switch slot {
        case .skill1: return actionPoint(x: -163, y: 76)
        case .skill2: return actionPoint(x: -93, y: 69)
        case .skill3: return actionPoint(x: -77, y: -3)
        case .ultimate, .passive: return actionPoint(x: -76, y: -72)
        }
    }

    func levelBadgeCenter(_ slot: SkillSlot) -> CGPoint {
        switch slot {
        case .skill1: return actionPoint(x: -210, y: 30)
        case .skill2: return actionPoint(x: -142, y: 19)
        case .skill3: return actionPoint(x: -138, y: -32)
        case .ultimate, .passive: return actionPoint(x: -123, y: -129)
        }
    }

    func spellCenter(_ index: Int) -> CGPoint {
        index == 0 ? actionPoint(x: -204, y: -26) : actionPoint(x: -181, y: -90)
    }

    var recallCenter: CGPoint { actionPoint(x: -218, y: 89) }

    /// 右側クラスタの内側（画面中央側）の端。
    var clusterInnerEdge: CGFloat {
        let r = recallCenter.x
        return leftHanded ? r + recallDiameter / 2 + 8 : r - recallDiameter / 2 - 8
    }

    // MARK: キャンセル領域（照準中のみ表示）

    var cancelRadius: CGFloat { 38 * scale }
    var cancelCenter: CGPoint {
        mirrored(CGPoint(x: trailingEdge - 64 * scale, y: topEdge + 58 * scale))
    }

    /// スキル照準の最大ドラッグ量（pt）。
    var aimDragRadius: CGFloat { 84 * scale }

    // MARK: スティック

    var joystickRadius: CGFloat { 58 * scale }
    var joystickKnob: CGFloat { 48 * scale }
    var joystickRest: CGPoint {
        mirrored(CGPoint(x: leadingEdge + 16 * scale + joystickRadius, y: bottomEdge - 24 * scale - joystickRadius))
    }

    /// フローティングスティックの受付領域。
    var joystickZone: CGRect {
        let top = minimapFrame.maxY + 10
        let panelNear = leftHanded ? size.width - (heroPanelCenterX + heroPanelWidth / 2) : heroPanelCenterX - heroPanelWidth / 2
        let w = max(140, min(size.width * 0.42, panelNear - 4))
        return CGRect(x: leftHanded ? size.width - w : 0, y: top, width: w, height: size.height - top)
    }

    // MARK: 上部

    var minimapSize: CGFloat { min(158, max(118, size.height * 0.34)) }
    var minimapFrame: CGRect {
        CGRect(x: leadingEdge + 2, y: topEdge, width: minimapSize, height: minimapSize)
    }

    var topButtonSize: CGFloat { 44 }

    // MARK: 下部中央のヒーローパネル

    var heroPanelWidth: CGFloat { 290 * min(scale, 1.08) }

    /// スティックとスキル群の間の中央。
    var heroPanelCenterX: CGFloat {
        let joyEdge = leftHanded ? joystickRest.x - joystickRadius : joystickRest.x + joystickRadius
        let clusterEdge = clusterInnerEdge
        return (joyEdge + clusterEdge) / 2
    }

}
