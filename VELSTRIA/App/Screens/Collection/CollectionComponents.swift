import SwiftUI
import VelstriaCore

// 担当: ui-collection。コレクション/ストア共通の小部品。

/// フィルタ用チップ（見た目はコンパクト、タップ領域は 44pt）。
struct CollectionFilterChip: View {
    let title: String
    var symbol: String?
    var color: Color = Theme.cyan
    let isSelected: Bool
    /// false で記号のみ（選択中は常に名前も表示）。
    var showsTitle = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.8) : color)
                }
                if showsTitle || isSelected || symbol == nil {
                    Text(title)
                        .font(Theme.body(13))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Theme.textPrimary)
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 44)
            .frame(height: 32)
            .background(Capsule().fill(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(isSelected ? Color.white.opacity(0.6) : color.opacity(0.35), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

/// セクション見出し。
struct CollectionSectionTitle: View {
    let title: String
    var symbol: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            Text(title)
                .font(Theme.heading(15))
                .foregroundStyle(Theme.textPrimary)
            Rectangle()
                .fill(LinearGradient(colors: [Theme.panelStroke, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            if let trailing {
                Text(trailing)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 難易度（★1〜5）。
struct CollectionDifficultyStars: View {
    let value: Int
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i <= value ? Theme.gold : Theme.textSecondary.opacity(0.5))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("難易度 \(value)/5（\(CollectionStyle.difficultyName(value))）",
                              "Difficulty \(value) of 5 (\(CollectionStyle.difficultyName(value)))"))
    }
}

/// ロール表示（色 + 記号 + 名前）。
struct CollectionRoleTag: View {
    let role: Role
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Theme.roleSymbol(role))
                .font(.system(size: compact ? 10 : 12, weight: .bold))
            if !compact {
                Text(MasterText.role(role))
                    .font(Theme.body(12))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.roleColor(role))
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.roleColor(role).opacity(0.16)))
        .overlay(Capsule().stroke(Theme.roleColor(role).opacity(0.45), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(MasterText.role(role))
    }
}

/// 小さな情報タグ（非インタラクティブ）。
struct CollectionInfoTag: View {
    let text: String
    var symbol: String?
    var color: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(Theme.body(11)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.8))
    }
}

/// スキル枠バッジ（P / 1 / 2 / 3 / U）。
struct CollectionSkillSlotBadge: View {
    let slot: SkillSlot
    var size: CGFloat = 26

    var body: some View {
        let c = CollectionStyle.slotColor(slot)
        Text(CollectionStyle.slotBadge(slot))
            .font(.system(size: size * 0.5, weight: .black, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [c, c.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            )
            .accessibilityLabel(CollectionStyle.slotName(slot))
    }
}

/// 空状態。
struct CollectionEmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(Theme.heading(15))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 戦闘内 Gold の価格表示。
struct GoldPriceLabel: View {
    let amount: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.circle.fill")
                .font(.system(size: size * 0.9, weight: .bold))
                .foregroundStyle(CollectionStyle.goldColor)
            Text(CollectionStyle.number(amount, digits: 0))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(CollectionStyle.goldColor)
                .monospacedDigit()
        }
        .accessibilityElement()
        .accessibilityLabel(L("\(Int(amount)) ゴールド", "\(Int(amount)) gold"))
    }
}

/// Lv1 と Lv最大 の 2 段バー。
struct CollectionStatBar: View {
    let label: String
    let symbol: String
    let lv1: Double
    let lvMax: Double
    let maxValue: Double
    let growth: String?
    let color: Color
    var digits = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 78, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(color.opacity(0.35))
                        .frame(width: max(4, w * min(1, lvMax / maxValue)))
                    Capsule().fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, w * min(1, lv1 / maxValue)))
                }
            }
            .frame(height: 8)
            Text(CollectionStyle.number(lv1, digits: digits))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, alignment: .trailing)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            Text(CollectionStyle.number(lvMax, digits: digits))
                .font(Theme.mono(11))
                .foregroundStyle(color)
                .frame(width: 44, alignment: .leading)
            Text(growth ?? "")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) Lv1 \(CollectionStyle.number(lv1, digits: digits)), Lv\(Balance.maxLevel) \(CollectionStyle.number(lvMax, digits: digits))")
    }
}

// MARK: - 手続き生成アイコン

/// 角を切り落とした矩形（Tier 枠）。chamfer = 0 は角丸矩形扱い。
struct CollectionChamferShape: Shape {
    var chamfer: CGFloat

    func path(in rect: CGRect) -> Path {
        guard chamfer > 0 else {
            return Path(roundedRect: rect, cornerRadius: rect.width * 0.2, style: .continuous)
        }
        let c = min(rect.width, rect.height) * chamfer
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

/// 正多角形（ルーン枠など）。
struct CollectionPolygonShape: Shape {
    var sides: Int
    var rotation: Double = -.pi / 2

    func path(in rect: CGRect) -> Path {
        let n = max(3, sides)
        let r = Double(min(rect.width, rect.height)) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<n {
            let a = rotation + Double(i) * 2 * .pi / Double(n)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// 装備アイコン（カテゴリ = 色と記号、Tier = 枠形状と装飾、ID = 模様の角度）。
struct ItemIconView: View {
    let item: ItemDef
    var size: CGFloat = 52

    private var chamfer: CGFloat {
        switch item.tier {
        case ...1: return 0
        case 2: return 0.16
        default: return 0.28
        }
    }

    var body: some View {
        let color = CollectionStyle.categoryColor(item.category)
        let tierColor = CollectionStyle.tierColor(item.tier)
        let number = Int(item.itemID.dropFirst(2)) ?? 0
        let angle = Double((number * 37) % 180)
        let shape = CollectionChamferShape(chamfer: chamfer)
        ZStack {
            shape.fill(LinearGradient(colors: [color.opacity(0.55), Color.black.opacity(0.75)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            // ID 毎の模様（同カテゴリ・同 Tier の装備を見分ける）
            Canvas { ctx, sz in
                let step = sz.width / 6
                ctx.rotate(by: .degrees(angle))
                for i in -8...8 {
                    let x = Double(i) * step
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: -sz.height * 1.5))
                    line.addLine(to: CGPoint(x: x, y: sz.height * 1.5))
                    ctx.stroke(line, with: .color(.white.opacity(i % 2 == 0 ? 0.08 : 0.04)), lineWidth: step * 0.35)
                }
            }
            .clipShape(shape)
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.7), .clear], center: .center, startRadius: 1, endRadius: size * 0.42))
                .padding(size * 0.08)
            Image(systemName: CollectionStyle.categorySymbol(item.category))
                .font(.system(size: size * 0.38, weight: .black))
                .foregroundStyle(LinearGradient(colors: [.white, color.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .shadow(color: color.opacity(0.8), radius: size * 0.06)
            // Tier の印
            HStack(spacing: size * 0.04) {
                ForEach(0..<max(1, min(3, item.tier)), id: \.self) { _ in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: size * 0.11, weight: .bold))
                        .foregroundStyle(tierColor)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, size * 0.07)
            shape.stroke(LinearGradient(colors: [tierColor, tierColor.opacity(0.45)], startPoint: .top, endPoint: .bottom),
                         lineWidth: item.tier >= 3 ? max(2, size * 0.05) : max(1.2, size * 0.03))
            if item.tier >= 3 {
                shape.stroke(tierColor.opacity(0.35), lineWidth: 1).padding(size * 0.07)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: item.tier >= 3 ? tierColor.opacity(0.35) : .clear, radius: size * 0.08)
        .accessibilityHidden(true)
    }
}

/// ルーンアイコン（パス = 色と記号、Tier = 枠の角数）。
struct RuneIconView: View {
    let path: RunePath
    let tier: Int
    var size: CGFloat = 40
    var dimmed = false

    var body: some View {
        let color = CollectionStyle.runePathColor(path)
        let sides = tier <= 1 ? 4 : (tier == 2 ? 6 : 8)
        let shape = CollectionPolygonShape(sides: sides, rotation: tier <= 1 ? -.pi / 2 : -.pi / 2 + .pi / Double(sides))
        ZStack {
            shape.fill(RadialGradient(colors: [color.opacity(dimmed ? 0.25 : 0.8), Color.black.opacity(0.7)],
                                      center: .init(x: 0.4, y: 0.35), startRadius: 1, endRadius: size * 0.7))
            shape.stroke(color.opacity(dimmed ? 0.4 : 1), lineWidth: max(1.2, size * 0.05))
            Image(systemName: CollectionStyle.runePathSymbol(path))
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white.opacity(dimmed ? 0.45 : 1))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// オーラリング付きヒーロー表示（詳細・購入演出用）。
struct HeroAuraPortrait: View {
    let heroID: String
    var size: CGFloat = 120
    var color: Color = Theme.cyan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2.0)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.45 + 0.2 * pulse), .clear],
                                         center: .center, startRadius: size * 0.2, endRadius: size * 0.95))
                    .frame(width: size * 1.9, height: size * 1.9)
                Circle()
                    .stroke(AngularGradient(colors: [color, .white.opacity(0.9), color.opacity(0.1), color.opacity(0.7), color],
                                            center: .center), lineWidth: size * 0.035)
                    .frame(width: size * 1.42, height: size * 1.42)
                    .rotationEffect(.radians(t * 0.9))
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                    .frame(width: size * 1.6, height: size * 1.6)
                    .rotationEffect(.radians(-t * 1.4))
                Circle()
                    .trim(from: 0.5, to: 0.62)
                    .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.022, lineCap: .round))
                    .frame(width: size * 1.6, height: size * 1.6)
                    .rotationEffect(.radians(-t * 1.4))
                ForEach(0..<6, id: \.self) { i in
                    let a = t * 0.6 + Double(i) * .pi / 3
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: size * 0.035, height: size * 0.035)
                        .offset(x: cos(a) * size * 0.71, y: sin(a) * size * 0.71)
                }
                HeroPortraitView(heroID: heroID, size: size)
                    .shadow(color: color.opacity(0.6), radius: 10 + 6 * pulse)
                    .scaleEffect(1 + 0.012 * pulse)
            }
        }
        .frame(width: size * 1.7, height: size * 1.7)
    }
}
