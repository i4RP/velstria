import SwiftUI
import VelstriaCore

// 担当: ui-flow。フロー系画面（ホーム・メタ・対戦前後）で共有する部品。

// MARK: - 操作フィードバック

/// 効果音と触覚をまとめて鳴らす。
@MainActor
enum FlowFX {
    static func tap(_ app: AppModel) {
        app.audio.play(.uiTap)
        app.haptics.tap()
    }

    static func confirm(_ app: AppModel) {
        app.audio.play(.uiConfirm)
        app.haptics.impact(.medium)
    }

    static func back(_ app: AppModel) {
        app.audio.play(.uiBack)
        app.haptics.tap()
    }

    static func reward(_ app: AppModel) {
        app.audio.play(.reward)
        app.haptics.success()
    }

    static func error(_ app: AppModel) {
        app.audio.play(.uiError)
        app.haptics.warning()
    }
}

// MARK: - 形状

/// 4 方向に尖った星（ロゴ・装飾用）。
struct FourPointStar: Shape {
    var innerRatio: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<8 {
            let ang = Double(i) * .pi / 4 - .pi / 2
            let rr = i.isMultiple(of: 2) ? r : r * innerRatio
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * rr, y: c.y + CGFloat(sin(ang)) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// 尖り頂点が上の六角形（ランク紋章）。
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<6 {
            let ang = Double(i) * .pi / 3 - .pi / 2
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * r, y: c.y + CGFloat(sin(ang)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 星環（ロゴ・ショーケースの背景演出）

/// 傾いた光の輪の上を星が周回するアニメーション。SwiftUI の Canvas のみで描く。
struct StarRingView: View {
    var tint: Color = Theme.cyan
    var accent: Color = Theme.gold
    /// 1 秒あたりの回転数。
    var speed: Double = 0.08
    var starCount = 26
    var tilt: Double = -12
    var showsCore = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(in: &ctx, size: size, time: t)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let rx = size.width * 0.47
        let ry = size.height * 0.20
        let tiltRad = tilt * .pi / 180
        let ring = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            .applying(CGAffineTransform(rotationAngle: tiltRad).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))

        // 輪の発光（ぼかし層 + 芯）
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            layer.stroke(ring, with: .color(tint.opacity(0.55)), lineWidth: 6)
        }
        ctx.stroke(ring, with: .linearGradient(Gradient(colors: [tint.opacity(0.2), accent.opacity(0.9), tint.opacity(0.9), tint.opacity(0.2)]),
                                              startPoint: CGPoint(x: c.x - rx, y: c.y), endPoint: CGPoint(x: c.x + rx, y: c.y)),
                   lineWidth: 1.6)

        // 中心核
        if showsCore {
            let coreR = min(size.width, size.height) * 0.16
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: coreR * 0.6))
                layer.fill(Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR, width: coreR * 2, height: coreR * 2)),
                           with: .color(tint.opacity(0.35)))
            }
            let pulse = 1 + 0.08 * sin(time * 2.2)
            let sr = coreR * 0.9 * pulse
            let star = FourPointStar(innerRatio: 0.22).path(in: CGRect(x: c.x - sr, y: c.y - sr, width: sr * 2, height: sr * 2))
            ctx.fill(star, with: .linearGradient(Gradient(colors: [.white, accent]), startPoint: CGPoint(x: c.x, y: c.y - sr),
                                                 endPoint: CGPoint(x: c.x, y: c.y + sr)))
        }

        // 周回する星（手前ほど明るく大きい）
        let base = time * speed * 2 * .pi
        for i in 0..<starCount {
            let a = base + Double(i) / Double(starCount) * 2 * .pi
            let lx = rx * CGFloat(cos(a))
            let ly = ry * CGFloat(sin(a))
            let x = c.x + lx * CGFloat(cos(tiltRad)) - ly * CGFloat(sin(tiltRad))
            let y = c.y + lx * CGFloat(sin(tiltRad)) + ly * CGFloat(cos(tiltRad))
            let depth = (sin(a) + 1) / 2
            let r = CGFloat(1.0 + 2.2 * depth) * (i % 5 == 0 ? 1.6 : 1.0)
            let color = i % 5 == 0 ? accent : Color.white
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(color.opacity(0.25 + 0.7 * depth)))
        }
    }
}

/// VELSIA のマスターロゴ。タイトル・副題・星環を単一アートとして表示する。
struct VelstriaLogoView: View {
    var scale: CGFloat = 1

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 610 * scale, height: 285 * scale)
            .shadow(color: Theme.cyan.opacity(0.28), radius: 24 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("VELSIA " + L("星環の戦場", "Star Ring Arena"))
    }
}

// MARK: - 修飾

/// ゆっくり明滅する発光。
struct GlowPulse: ViewModifier {
    var color: Color
    var radius: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.shadow(color: color.opacity(0.6), radius: radius * 0.7)
        } else {
            content.phaseAnimator([false, true]) { view, on in
                view.shadow(color: color.opacity(on ? 0.9 : 0.35), radius: on ? radius : radius * 0.45)
            } animation: { _ in .easeInOut(duration: 1.4) }
        }
    }
}

/// ガラス調の面（Panel より軽い、タイルやカード向け）。
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 14
    var tint: Color = Theme.panelStroke
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(highlighted ? 0.16 : 0.09), Theme.panel.opacity(0.75)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LinearGradient(colors: [tint.opacity(highlighted ? 1 : 0.8), tint.opacity(0.15)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: highlighted ? 1.6 : 1)
            )
    }
}

extension View {
    func glowPulse(_ color: Color, radius: CGFloat = 16) -> some View { modifier(GlowPulse(color: color, radius: radius)) }
    func glass(cornerRadius: CGFloat = 14, tint: Color = Theme.panelStroke, highlighted: Bool = false) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, tint: tint, highlighted: highlighted))
    }
}

// MARK: - 小物

/// 未読数などのバッジ。
struct FlowCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(Theme.danger))
                .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}

/// 丸いアイコンボタン（44pt 以上）。
struct FlowIconButton: View {
    let symbol: String
    let label: String
    var badge = 0
    var identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Theme.panelStroke, lineWidth: 1))
                .overlay(alignment: .topTrailing) { FlowCountBadge(count: badge).offset(x: 4, y: -2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(label) \(L("未読", "unread")) \(badge)" : label)
        .accessibilityIdentifier(identifier)
    }
}

/// 進捗バー。
struct FlowProgressBar: View {
    var value: Double
    var tint: Color = Theme.cyan
    var height: CGFloat = 6
    var track: Color = Color.white.opacity(0.12)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value.isFinite ? value : 0)) * geo.size.width)
                    .shadow(color: tint.opacity(0.6), radius: 4)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((max(0, min(1, value.isFinite ? value : 0)) * 100).rounded()))%")
    }
}

/// 選択チップ（フィルタ・難易度など）。
struct FlowChip: View {
    let title: String
    var symbol: String?
    var selected: Bool
    var tint: Color = Theme.gold

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
            Text(title).font(Theme.heading(13)).lineLimit(1)
        }
        .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.08))))
        .overlay(Capsule().stroke(selected ? Color.white.opacity(0.6) : Theme.panelStroke, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// 空状態の表示。
struct FlowEmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.cyan.opacity(0.8))
                .glowPulse(Theme.cyan, radius: 10)
            Text(title)
                .font(Theme.heading(17))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// セクション見出し。
struct FlowSectionTitle: View {
    let title: String
    var symbol: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.gold)
            }
            Text(title).font(Theme.heading(15)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 数値の統計セル。
struct FlowStatCell: View {
    let title: String
    let value: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glass(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

/// 評価（S/A/B/C）バッジ。
struct GradeBadge: View {
    let grade: String
    var size: CGFloat = 28

    static func color(_ grade: String) -> Color {
        switch grade {
        case "S": return Theme.gold
        case "A": return Theme.cyan
        case "B": return Theme.success
        default: return Color(white: 0.7)
        }
    }

    var body: some View {
        Text(grade)
            .font(.system(size: size * 0.62, weight: .black, design: .serif))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: size, height: size)
            .background(HexagonShape().fill(LinearGradient(colors: [.white, Self.color(grade)], startPoint: .top, endPoint: .bottom)))
            .overlay(HexagonShape().stroke(Color.white.opacity(0.7), lineWidth: 1))
            .shadow(color: Self.color(grade).opacity(0.6), radius: size * 0.15)
            .accessibilityLabel(L("評価 \(grade)", "Grade \(grade)"))
    }
}

/// MVP バッジ。
struct MVPBadge: View {
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").font(.system(size: compact ? 9 : 12, weight: .bold))
            if !compact { Text("MVP").font(.system(size: 12, weight: .black, design: .rounded)) }
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(Capsule().fill(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom)))
        .accessibilityLabel("MVP")
    }
}

/// ロール記号付きラベル。
struct RoleLabel: View {
    let role: Role
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Theme.roleSymbol(role)).font(.system(size: size, weight: .bold))
            Text(MasterText.role(role)).font(Theme.body(size))
        }
        .foregroundStyle(Theme.roleColor(role))
        .accessibilityElement(children: .combine)
    }
}

/// ランク紋章（形 + 記号で識別できる）。
struct RankEmblemView: View {
    let tier: RankTier
    var size: CGFloat = 40

    var body: some View {
        let colors = FlowText.tierColors(tier)
        ZStack {
            HexagonShape()
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            HexagonShape()
                .stroke(LinearGradient(colors: [.white.opacity(0.9), colors[0].opacity(0.4)], startPoint: .top, endPoint: .bottom),
                        lineWidth: max(1, size * 0.05))
            HexagonShape()
                .insetHex(by: size * 0.12)
                .stroke(Color.white.opacity(0.35), lineWidth: max(0.5, size * 0.02))
            Image(systemName: FlowText.tierSymbol(tier))
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .frame(width: size, height: size)
        .shadow(color: colors[0].opacity(0.55), radius: size * 0.18)
        .accessibilityLabel(RankService.tierName(tier))
    }
}

private extension HexagonShape {
    func insetHex(by amount: CGFloat) -> some Shape {
        InsetHexagon(amount: amount)
    }
}

private struct InsetHexagon: Shape {
    var amount: CGFloat
    func path(in rect: CGRect) -> Path { HexagonShape().path(in: rect.insetBy(dx: amount, dy: amount)) }
}

/// ランクの星（最大 3）。
struct RankStarsView: View {
    let stars: Int
    var maxStars = 3
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<maxStars, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < stars ? Theme.gold : Theme.textSecondary.opacity(0.6))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("星 \(stars) / \(maxStars)", "\(stars) of \(maxStars) stars"))
    }
}

/// 現在ランクの 1 行表示（紋章 + 名称 + 星/ポイント）。
struct RankInlineView: View {
    let rank: RankState
    var emblemSize: CGFloat = 22
    var font: Font = Theme.body(12)

    var body: some View {
        HStack(spacing: 6) {
            RankEmblemView(tier: rank.tier, size: emblemSize)
            Text(RankService.displayName(rank))
                .font(font)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if rank.tier != .starRingSovereign {
                RankStarsView(stars: rank.stars, size: emblemSize * 0.45)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// メール・報酬の添付チップ。
struct AttachmentChip: View {
    let attachment: MailAttachment
    var claimed = false
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if claimed {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.success)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
        .opacity(claimed ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch attachment.kind {
        case .coin: return "star.circle.fill"
        case .gem: return "diamond.fill"
        case .cosmetic: return "sparkles"
        case .hero: return "person.crop.circle.badge.plus"
        case .passXP: return "bolt.fill"
        }
    }

    private var tint: Color {
        switch attachment.kind {
        case .coin: return Theme.gold
        case .gem: return Theme.cyan
        case .cosmetic: return Color(red: 0.8, green: 0.55, blue: 1.0)
        case .hero: return Theme.success
        case .passXP: return Color(red: 1.0, green: 0.62, blue: 0.3)
        }
    }

    private var title: String {
        FlowText.attachmentTitle(attachment, master: app.master)
    }
}

/// 自動折り返しの横並び（チップ用）。
struct FlowWrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// カプセル型のタブ切替（各タブ 44pt 以上）。
struct FlowTabBar<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: String
        let symbol: String
        let identifier: String
    }

    let items: [Item]
    @Binding var selection: Tab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let selected = item.tab == selection
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = item.tab }
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(Theme.heading(14))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
                        .background {
                            if selected {
                                Capsule().fill(LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                    .matchedGeometryEffect(id: "flowTab", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.identifier)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(Theme.panelStroke, lineWidth: 1))
        .fixedSize()
    }
}

/// 閉じる（×）ボタン。
struct FlowCloseButton: View {
    var identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Theme.panelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("閉じる", "Close"))
        .accessibilityIdentifier(identifier)
    }
}

/// アカウントレベルと XP バー。
struct AccountLevelBar: View {
    let level: Int
    let xp: Int
    var width: CGFloat? = 120

    var body: some View {
        let required = FlowAccountXP.required(forLevel: level)
        HStack(spacing: 6) {
            Text("Lv.\(level)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.gold)
                .monospacedDigit()
            FlowProgressBar(value: Double(xp) / Double(max(1, required)), tint: Theme.cyan, height: 5)
                .frame(width: width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("アカウントレベル \(level)、経験値 \(xp) / \(required)", "Account level \(level), XP \(xp) of \(required)"))
    }
}

// MARK: - ヒーロー

/// ヒーローのカード（グリッド用）。所持していない場合は暗く錠前と価格を出す。
struct HeroGridCell: View {
    let hero: HeroDef
    var selected = false
    var locked = false
    var unavailable = false
    var unavailableLabel: String?
    var price: Int?
    var size: CGFloat = 58

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                HeroPortraitView(heroID: hero.heroID, size: size)
                    .saturation(locked || unavailable ? 0.1 : 1)
                    .opacity(locked || unavailable ? 0.45 : 1)
                if unavailable, let unavailableLabel {
                    Text(unavailableLabel)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.danger.opacity(0.9)))
                        .rotationEffect(.degrees(-12))
                } else if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .stroke(selected ? Theme.gold : .clear, lineWidth: 3)
                    .shadow(color: Theme.gold.opacity(selected ? 0.9 : 0), radius: 6)
            )
            .scaleEffect(selected ? 1.06 : 1)
            Text(MasterText.hero(hero))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Theme.gold : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size + 10)
            if locked, let price {
                HStack(spacing: 2) {
                    Image(systemName: "star.circle.fill").font(.system(size: 9))
                    Text(price.formatted()).font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(Theme.gold)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .animation(.spring(duration: 0.25), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        var s = "\(MasterText.hero(hero)) \(MasterText.role(hero.role))"
        if unavailable { s += " " + (unavailableLabel ?? L("選択不可", "Unavailable")) }
        if locked { s += " " + L("未所持", "Locked") }
        if locked, let price { s += " \(price) " + L("コイン", "coins") }
        return s
    }
}

// MARK: - 表示テキスト・スタイル表

enum FlowText {
    static func position(_ p: LanePosition) -> String {
        switch p {
        case .top: return L("トップ", "Top")
        case .jungle: return L("ジャングル", "Jungle")
        case .mid: return L("ミッド", "Mid")
        case .carry: return L("ボット", "Bot")
        case .support: return L("サポート", "Support")
        }
    }

    static func positionSymbol(_ p: LanePosition) -> String {
        switch p {
        case .top: return "arrow.up.circle.fill"
        case .jungle: return "leaf.circle.fill"
        case .mid: return "arrow.up.right.circle.fill"
        case .carry: return "arrow.right.circle.fill"
        case .support: return "heart.circle.fill"
        }
    }

    static func difficulty(_ d: Difficulty) -> String {
        switch d {
        case .easy: return L("かんたん", "Easy")
        case .normal: return L("ふつう", "Normal")
        case .hard: return L("むずかしい", "Hard")
        }
    }

    static func difficultySymbol(_ d: Difficulty) -> String {
        switch d {
        case .easy: return "leaf.fill"
        case .normal: return "flame.fill"
        case .hard: return "bolt.fill"
        }
    }

    static func mode(_ m: MatchMode) -> String {
        switch m {
        case .standard: return L("通常戦", "Standard")
        case .ranked: return L("ランク戦", "Ranked")
        case .practice: return L("練習場", "Practice")
        case .tutorial: return L("チュートリアル", "Tutorial")
        case .spectate: return L("観戦", "Spectate")
        case .brawl: return L("乱闘", "Brawl")
        case .custom: return L("カスタム", "Custom")
        case .magicChess: return L("マジックチェス", "Magic Chess")
        }
    }

    static func team(_ t: Team) -> String {
        switch t {
        case .blue: return L("ブルーチーム", "Blue Team")
        case .red: return L("レッドチーム", "Red Team")
        case .neutral: return L("中立", "Neutral")
        }
    }

    static func teamSymbol(_ t: Team) -> String {
        switch t {
        case .blue: return "shield.fill"
        case .red: return "flame.fill"
        case .neutral: return "circle.fill"
        }
    }

    static func endReason(_ r: EndReason) -> String {
        switch r {
        case .coreDestroyed: return L("スターコア破壊", "Star Core destroyed")
        case .surrender: return L("降参", "Surrender")
        case .aborted: return L("中断", "Aborted")
        case .timeLimit: return L("時間切れ", "Time limit")
        }
    }

    /// 秒 → "mm:ss"。
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 言語・書式ごとに使い回す（一覧の各行で DateFormatter を作り直さない）。UI スレッドからのみ使う。
    nonisolated(unsafe) private static var dateFormatters: [String: DateFormatter] = [:]

    static func date(_ d: Date, time: Bool = true) -> String {
        let english = Loc.isEnglish
        let format = english ? (time ? "MMM d, yyyy HH:mm" : "MMM d, yyyy") : (time ? "yyyy/MM/dd HH:mm" : "yyyy/MM/dd")
        let key = (english ? "en|" : "ja|") + format
        if let f = dateFormatters[key] { return f.string(from: d) }
        let f = DateFormatter()
        f.locale = Locale(identifier: english ? "en_US" : "ja_JP")
        f.dateFormat = format
        dateFormatters[key] = f
        return f.string(from: d)
    }

    static func compactNumber(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 10_000 { return String(format: "%.1fk", v / 1000) }
        return Int(v.rounded()).formatted()
    }

    static func kda(_ k: Int, _ d: Int, _ a: Int) -> String { "\(k) / \(d) / \(a)" }

    // MARK: バトルスペル（DESIGN §7）

    static func spellName(_ id: String) -> String {
        guard let def = MasterData.shared.spell(id) else { return id }
        return MasterText.spell(def)
    }

    static func spellDescription(_ id: String) -> String {
        switch id {
        case "BS01": return L("指定方向へ 400 瞬間移動する。", "Teleport 400 units in a direction.")
        case "BS02": return L("全ての行動妨害を解除し、1.5 秒間無効にする。", "Remove all crowd control and become immune for 1.5s.")
        case "BS03": return L("自身と近くの味方 1 人の HP を 15% 回復し、移動速度 +20%。", "Heal yourself and a nearby ally for 15% HP and gain 20% move speed.")
        case "BS04": return L("3 秒間、最大 HP 20% のシールドを得る。", "Gain a shield equal to 20% max HP for 3s.")
        case "BS05": return L("近くのミニオン・モンスターに確定ダメージ。ジャングルに必須。", "Deal true damage to a nearby minion or monster. Required for Jungle.")
        case "BS06": return L("5 秒間、移動速度 +40%。", "Gain 40% move speed for 5s.")
        case "BS07": return L("敵ヒーローを燃やし継続ダメージ、回復量 −50%。", "Burn an enemy hero for true damage over time and cut healing by 50%.")
        case "BS08": return L("1.5 秒間ステルス状態になり、移動速度 +25%。", "Become stealthed for 1.5s and gain 25% move speed.")
        case "BS09": return L("3 秒の詠唱後、味方タワーか泉へ転移する。", "After a 3s channel, teleport to an allied tower or the fountain.")
        case "BS10": return L("敵ヒーローを 40% スローし、与ダメージ −30%（2.5 秒）。", "Slow an enemy hero by 40% and reduce their damage by 30% for 2.5s.")
        default: return MasterData.shared.spell(id).map { MasterText.description(id: id, ja: $0.description) } ?? ""
        }
    }

    static func spellSymbol(_ id: String) -> String {
        switch id {
        case "BS01": return "bolt.fill"
        case "BS02": return "sparkles"
        case "BS03": return "heart.fill"
        case "BS04": return "shield.fill"
        case "BS05": return "pawprint.fill"
        case "BS06": return "hare.fill"
        case "BS07": return "flame.fill"
        case "BS08": return "eye.slash.fill"
        case "BS09": return "arrow.uturn.backward.circle.fill"
        case "BS10": return "link"
        default: return "questionmark"
        }
    }

    static func spellColor(_ id: String) -> Color {
        switch id {
        case "BS01": return Color(red: 0.95, green: 0.78, blue: 0.25)
        case "BS02": return Color(red: 0.55, green: 0.85, blue: 1.0)
        case "BS03": return Color(red: 0.35, green: 0.85, blue: 0.55)
        case "BS04": return Color(red: 0.45, green: 0.62, blue: 0.95)
        case "BS05": return Color(red: 0.55, green: 0.75, blue: 0.30)
        case "BS06": return Color(red: 0.30, green: 0.85, blue: 0.85)
        case "BS07": return Color(red: 1.0, green: 0.45, blue: 0.25)
        case "BS08": return Color(red: 0.62, green: 0.50, blue: 0.95)
        case "BS09": return Color(red: 0.40, green: 0.60, blue: 1.0)
        case "BS10": return Color(red: 0.85, green: 0.40, blue: 0.75)
        default: return Color.gray
        }
    }

    // MARK: ランク

    static func tierColors(_ t: RankTier) -> [Color] {
        switch t {
        case .meteorite: return [Color(red: 0.62, green: 0.50, blue: 0.42), Color(red: 0.26, green: 0.20, blue: 0.20)]
        case .silverRing: return [Color(red: 0.86, green: 0.89, blue: 0.94), Color(red: 0.42, green: 0.47, blue: 0.56)]
        case .goldRing: return [Color(red: 1.0, green: 0.84, blue: 0.42), Color(red: 0.62, green: 0.40, blue: 0.10)]
        case .whiteStar: return [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.55, green: 0.66, blue: 0.88)]
        case .azureCrystal: return [Color(red: 0.45, green: 0.90, blue: 1.0), Color(red: 0.10, green: 0.32, blue: 0.75)]
        case .starCrown: return [Color(red: 0.84, green: 0.60, blue: 1.0), Color(red: 0.35, green: 0.15, blue: 0.62)]
        case .starRingSovereign: return [Color(red: 1.0, green: 0.86, blue: 0.48), Color(red: 0.92, green: 0.30, blue: 0.55)]
        }
    }

    static func tierSymbol(_ t: RankTier) -> String {
        switch t {
        case .meteorite: return "shield.fill"
        case .silverRing: return "circle.circle"
        case .goldRing: return "circle.circle.fill"
        case .whiteStar: return "star.fill"
        case .azureCrystal: return "diamond.fill"
        case .starCrown: return "crown.fill"
        case .starRingSovereign: return "sun.max.fill"
        }
    }

    // MARK: 添付

    static func attachmentTitle(_ a: MailAttachment, master: MasterData) -> String {
        switch a.kind {
        case .coin: return "\(a.amount.formatted()) " + L("コイン", "Coins")
        case .gem: return "\(a.amount.formatted()) " + L("ジェム", "Gems")
        case .passXP: return "\(a.amount.formatted()) " + L("パスXP", "Pass XP")
        case .cosmetic:
            if let id = a.refID, let c = master.cosmetic(id) { return MasterText.cosmetic(c) }
            return L("コスメ", "Cosmetic")
        case .hero:
            if let id = a.refID, let h = master.hero(id) { return MasterText.hero(h) }
            return L("ヒーロー", "Hero")
        }
    }

    /// 添付の一覧を 1 行の文字列に（トースト用）。
    static func attachmentsSummary(_ list: [MailAttachment], master: MasterData) -> String {
        list.map { attachmentTitle($0, master: master) }.joined(separator: "、")
    }
}

/// アカウント XP の必要量（Profile.accountXP は現在レベル内の XP として扱う）。
/// 報酬側（RewardService）の成長曲線「次のレベルまで 400 + 100×Lv」と一致させる。
enum FlowAccountXP {
    /// レベル L → L+1 に必要な XP。
    static func required(forLevel level: Int) -> Int {
        400 + 100 * max(1, level)
    }

    /// 試合前のレベル内 XP を逆算する（レベルアップを挟んでも正しく戻す）。0〜必要量に収める。
    static func xpBefore(levelBefore: Int, levelAfter: Int, xpAfter: Int, gained: Int) -> Int {
        var total = xpAfter - gained
        if levelAfter > levelBefore {
            for lv in levelBefore..<levelAfter { total += required(forLevel: lv) }
        }
        return min(max(0, total), required(forLevel: levelBefore))
    }
}
