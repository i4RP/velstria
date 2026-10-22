import SwiftUI
import VelstriaCore

// 試合の外の共通部品（採用案 Celestial Saber の質感: 藍の地・氷青の細い縁・面取りの角・明朝の見出し）。
// 同じ役割の部品はここの 1 つだけを使う: 空の状態（EmptyStateView）・見出し（SectionTitle）・進み具合（CelestialProgressBar）・
// 報酬のチップ（RewardChip）・タブ（CelestialTabs）。試合の中（App/Battle）では使わない。

/// 採用案の色と文字。
enum Celestial {
    /// 地の藍。
    static let ink = Color(red: 0.015, green: 0.045, blue: 0.09)
    static let inkRaised = Color(red: 0.05, green: 0.10, blue: 0.19)
    /// 縁と記号の氷青。
    static let ice = Color(red: 0.65, green: 0.84, blue: 1)

    /// 画面の題名・カードの名前（明朝）。
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    /// 見出し（明朝）。
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
}

/// 試合の外の画面の背景: 季節のキービジュアルをぼかして暗くした上に、上下の藍の帯（ホームの外側と同じ）。
struct CelestialBackdrop: View {
    var body: some View {
        // 絵は画面の大きさで切り抜く（scaledToFill の絵は縦横比で画面より大きくなり、そのままだと親を押し広げて中身がずれる。
        // SE では横に約 80pt 広がり「戻る」が画面の外へ出ていた）
        GeometryReader { geo in
            ZStack {
                Celestial.ink
                Image("CelestialLobby").resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 22)
                    .overlay(Color.black.opacity(0.66))
                LinearGradient(colors: [Celestial.ink.opacity(0.85), .clear, Celestial.ink.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - 空の状態

/// 中身が無いときの表示（記号・題名・補足）。
struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(Celestial.ice)
                .shadow(color: Celestial.ice.opacity(0.5), radius: 6)
            Text(title)
                .font(Celestial.heading(16))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 見出し

/// 区切りの見出し（記号・題名・右に消えていく細い線・右端の補足）。
struct SectionTitle: View {
    let title: String
    var symbol: String?
    var trailing: String?
    var tint: Color = Celestial.ice

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            }
            Text(title).font(Celestial.heading(15)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Rectangle()
                .fill(LinearGradient(colors: [Celestial.ice.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.7)
                .frame(minWidth: 8)
            if let trailing {
                Text(trailing).font(Theme.body(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 進み具合

/// 細い進み具合のバー（光る先端つき）。value は 0〜1。
struct CelestialProgressBar: View {
    var value: Double
    var tint: Color = Theme.cyan
    var height: CGFloat = 6
    var track: Color = Color.white.opacity(0.12)

    var body: some View {
        let v = value.isFinite ? min(1, max(0, value)) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: v > 0 ? max(geo.size.height, geo.size.width * v) : 0)
                    .shadow(color: tint.opacity(0.7), radius: 3)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((v * 100).rounded()))%")
    }
}

// MARK: - 報酬のチップ

/// 報酬の小さなチップ（絵 + 数量）。受け取り済みはチェックをつけて薄くする。
struct RewardChip: View {
    let attachment: MailAttachment
    var claimed = false

    var body: some View {
        HStack(spacing: 4) {
            RewardClaimIcon(attachment: attachment, size: 20)
            Text(RewardClaimText.chipText(attachment))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .monospacedDigit()
            if claimed {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.success)
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(HomeChamfer(cut: 5).fill(Celestial.ink.opacity(0.85)))
        .overlay(HomeChamfer(cut: 5).stroke(Celestial.ice.opacity(0.45), lineWidth: 0.6))
        .opacity(claimed ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RewardClaimText.name(attachment) + (claimed ? L("（受取済み）", " (claimed)") : ""))
    }
}

// MARK: - タブ

/// タブの 1 つ。badge は右肩の数（0 で非表示）。
struct CelestialTab<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String?
    var badge: Int = 0
    let identifier: String
    var id: String { identifier }
}

/// タブ（44pt 以上のタップ領域）。fills が真なら幅いっぱいに等分、偽なら中身の幅で並べる。
struct CelestialTabs<Value: Hashable>: View {
    let options: [CelestialTab<Value>]
    @Binding var selection: Value
    var axis: Axis = .horizontal
    var tint: Color = Theme.gold
    var fills = true
    var onChange: ((Value) -> Void)?

    var body: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            ForEach(options) { option in
                tab(option)
            }
        }
        .fixedSize(horizontal: !fills, vertical: false)
    }

    private func tab(_ option: CelestialTab<Value>) -> some View {
        let selected = option.value == selection
        let shape = HomeChamfer(cut: 7)
        return Button {
            guard selection != option.value else { return }
            withAnimation(.spring(duration: 0.25)) { selection = option.value }
            onChange?(option.value)
        } label: {
            HStack(spacing: 6) {
                if let symbol = option.symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(option.title)
                    .font(Celestial.heading(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if option.badge > 0 {
                    Text("\(option.badge)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold))
                }
            }
            .foregroundStyle(selected ? Color(red: 0.16, green: 0.10, blue: 0.03) : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: 44)
            .background(
                shape.fill(selected ? AnyShapeStyle(LinearGradient(colors: [HomeStyle.goldLight, tint], startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(Celestial.ink.opacity(0.8)))
            )
            .overlay(shape.stroke(selected ? HomeStyle.goldLight : Celestial.ice.opacity(0.4), lineWidth: selected ? 1 : 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(option.identifier)
        .accessibilityLabel(option.badge > 0 ? "\(option.title), \(L("受取可能", "claimable")) \(option.badge)" : option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
