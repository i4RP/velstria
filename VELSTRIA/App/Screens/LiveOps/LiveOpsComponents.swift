import SwiftUI
import VelstriaCore

// 担当: ui-liveops。ライブオプス系・設定系画面で共有する部品と表示用の書式。
// 他担当の型と衝突しないよう、共有する型には LiveOps 接頭辞を付ける。

// MARK: - 時刻

/// ミッション・イベントの更新時刻とカウントダウン表記。
enum LiveOpsClock {
    /// 次のデイリー更新（端末ローカル日付の翌 0:00。LiveOpsService.dayKey と同じ基準）。
    static func nextDailyReset(after now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
    }

    /// 次のウィークリー更新（ISO 週 = 月曜 0:00 始まり、端末ローカル）。
    static func nextWeeklyReset(after now: Date, calendar: Calendar = .current) -> Date {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        if let week = iso.dateInterval(of: .weekOfYear, for: now) { return week.end }
        return nextDailyReset(after: now, calendar: calendar).addingTimeInterval(6 * 86_400)
    }

    /// 残り時間の表記。1 日以上は「2日 3時間」、未満は「HH:MM:SS」。
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 {
            return L("\(days)日 \(hours)時間", "\(days)d \(hours)h")
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// 画面を開いたまま日付が変わった時の日替わり処理。
@MainActor
enum LiveOpsDayRollover {
    /// 最終ログイン日より日付が進んでいれば、起動時と同じ処理（ログインボーナス・デイリー / ウィークリーの更新）を行う。
    /// 端末時刻が過去に戻った場合は何もしない。処理した場合 true。
    @discardableResult
    static func refreshIfNeeded(app: AppModel, now: Date = Date()) -> Bool {
        guard needsRefresh(lastLoginDayKey: app.profile.lastLoginDayKey, today: LiveOpsService.dayKey(now)) else { return false }
        var p = app.profile
        LiveOpsService.onLaunch(profile: &p, master: app.master, now: now)
        app.profile = p
        return true
    }

    /// 日付キーは "yyyy-MM-dd" なので文字列比較で前後を判定できる。
    nonisolated static func needsRefresh(lastLoginDayKey: String, today: String) -> Bool {
        lastLoginDayKey.isEmpty || today > lastLoginDayKey
    }

    /// 画面の表示中、定期的に日付の変化を確認する（`.task` から呼ぶ。画面を閉じると終了）。
    static func watch(_ app: AppModel) async {
        while !Task.isCancelled {
            refreshIfNeeded(app: app)
            try? await Task.sleep(for: .seconds(15))
        }
    }
}

// MARK: - 書式

enum LiveOpsFormat {
    static var locale: Locale { Locale(identifier: Loc.isEnglish ? "en_US" : "ja_JP") }

    /// 試合時間などの「m:ss」表記。
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 「9月28日 19:30」/「Sep 28, 19:30」（24 時間表記）。
    static func dateTime(_ date: Date) -> String {
        formatter(template: "MMMdHHmm").string(from: date)
    }

    /// 「9月28日」/「Sep 28」。
    static func date(_ date: Date) -> String {
        formatter(template: "MMMd").string(from: date)
    }

    private static func formatter(template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    static func modeName(_ mode: MatchMode) -> String {
        switch mode {
        case .standard: return L("通常戦", "Standard")
        case .ranked: return L("ランク戦", "Ranked")
        case .practice: return L("練習場", "Practice")
        case .tutorial: return L("チュートリアル", "Tutorial")
        case .spectate: return L("観戦", "Spectate")
        }
    }

    static func modeSymbol(_ mode: MatchMode) -> String {
        switch mode {
        case .standard: return "shield.lefthalf.filled"
        case .ranked: return "crown.fill"
        case .practice: return "target"
        case .tutorial: return "graduationcap.fill"
        case .spectate: return "eye.fill"
        }
    }

    static func difficultyName(_ d: Difficulty) -> String {
        switch d {
        case .easy: return L("イージー", "Easy")
        case .normal: return L("ノーマル", "Normal")
        case .hard: return L("ハード", "Hard")
        }
    }

    static func difficultyDetail(_ d: Difficulty) -> String {
        switch d {
        case .easy: return L("反応が遅く、スキルの精度も控えめ", "Slow reactions, loose skill aim")
        case .normal: return L("標準的な判断と照準", "Balanced decisions and aim")
        case .hard: return L("素早い反応と集団行動", "Fast reactions and group play")
        }
    }

    static func positionName(_ p: LanePosition) -> String {
        switch p {
        case .top: return L("トップ", "Top")
        case .jungle: return L("ジャングル", "Jungle")
        case .mid: return L("ミッド", "Mid")
        case .carry: return L("キャリー", "Carry")
        case .support: return L("サポート", "Support")
        }
    }

    static func teamName(_ t: Team) -> String {
        switch t {
        case .blue: return L("ブルーチーム", "Blue Team")
        case .red: return L("レッドチーム", "Red Team")
        case .neutral: return L("中立", "Neutral")
        }
    }

    /// 色だけに頼らないチーム識別用の記号。
    static func teamSymbol(_ t: Team) -> String {
        switch t {
        case .blue: return "circle.fill"
        case .red: return "triangle.fill"
        case .neutral: return "square.fill"
        }
    }

    /// 文字列 ID から決定的な色相（イベントバナー等の装飾用）。
    static func hue(for id: String) -> Double {
        var acc: UInt64 = 1469598103934665603
        for u in id.unicodeScalars {
            acc = (acc ^ UInt64(u.value)) &* 1099511628211
        }
        return Double(acc % 360) / 360.0
    }
}

// MARK: - 部品

/// 進捗バー（0〜1）。
struct LiveOpsProgressBar: View {
    var fraction: Double
    var tint: Color = Theme.cyan
    var height: CGFloat = 8

    var body: some View {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        Capsule()
            .fill(Color.white.opacity(0.10))
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: f > 0 ? max(height, g.size.width * f) : 0)
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// 空状態の表示。
struct LiveOpsEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.cyan.opacity(0.85))
            Text(title)
                .font(Theme.heading(17))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .accessibilityElement(children: .combine)
    }
}

/// 小さなラベル（状態・種別表示）。
struct LiveOpsTag: View {
    let text: String
    var symbol: String?
    var color: Color = Theme.cyan

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
        .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.5))
    }
}

/// パネル見出し。
struct LiveOpsSectionHeader: View {
    let title: String
    var symbol: String?
    var tint: Color = Theme.gold

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Text(title)
                .foregroundStyle(Theme.textPrimary)
        }
        .font(Theme.heading(15))
        .accessibilityAddTraits(.isHeader)
    }
}

/// カウントダウン（1 秒毎に更新）。
struct LiveOpsCountdownLabel: View {
    /// 現在時刻 → 目標時刻（定期更新のように時刻をまたいで目標が変わる場合に対応）。
    private let target: (Date) -> Date
    private let prefix: String
    private let symbol: String
    private let tint: Color

    init(target: Date, prefix: String, symbol: String = "clock.fill", tint: Color = Theme.gold) {
        self.init(resetTarget: { _ in target }, prefix: prefix, symbol: symbol, tint: tint)
    }

    init(resetTarget: @escaping (Date) -> Date, prefix: String, symbol: String = "clock.fill", tint: Color = Theme.gold) {
        self.target = resetTarget
        self.prefix = prefix
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = LiveOpsClock.countdown(target(ctx.date).timeIntervalSince(ctx.date))
            let text = prefix.isEmpty ? remaining : "\(prefix) \(remaining)"
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(text).monospacedDigit().lineLimit(1)
            }
            .font(Theme.mono(12))
            .foregroundStyle(tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
        }
    }
}

/// セグメント選択肢。
struct LiveOpsSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String?
    /// 右肩のバッジ数（0 で非表示）。
    var badge: Int = 0
    let identifier: String
    var id: String { identifier }
}

/// 44pt 以上のタップ領域を持つセグメント選択。
struct LiveOpsSegmented<Value: Hashable>: View {
    let options: [LiveOpsSegmentOption<Value>]
    @Binding var selection: Value
    var axis: Axis = .horizontal
    var tint: Color = Theme.cyan
    var onChange: ((Value) -> Void)?

    var body: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            ForEach(options) { option in
                segment(option)
            }
        }
    }

    private func segment(_ option: LiveOpsSegmentOption<Value>) -> some View {
        let selected = option.value == selection
        return Button {
            guard selection != option.value else { return }
            selection = option.value
            onChange?(option.value)
        } label: {
            HStack(spacing: 6) {
                if let symbol = option.symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                }
                Text(option.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
            .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                   : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.5) : Theme.panelStroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(option.identifier)
        .accessibilityLabel(option.badge > 0 ? "\(option.title), \(L("受取可能", "claimable")) \(option.badge)" : option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 報酬の小チップ（アイコン + 数量）。
struct LiveOpsRewardChip: View {
    let attachment: MailAttachment

    var body: some View {
        HStack(spacing: 4) {
            RewardClaimIcon(attachment: attachment, size: 20)
            Text(RewardClaimText.chipText(attachment))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(.leading, 3)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RewardClaimText.name(attachment))
    }
}

/// 左から並べ、幅が足りなければ次の行へ折り返す配置（報酬チップなど）。
struct LiveOpsFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            // 1 つで行幅を超えるものは行幅に収める
            if maxWidth.isFinite && size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// 44pt の丸いアイコンボタン（削除・再抽選など）。
struct LiveOpsIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.textPrimary
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Theme.panelStroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// 共通ボタンスタイル（PrimaryButtonStyle / SecondaryButtonStyle）の見た目のまま、タップ領域を高さ 44pt 以上に広げる。
struct LiveOpsTallButtonStyle<Base: ButtonStyle>: ButtonStyle {
    let base: Base

    func makeBody(configuration: Configuration) -> some View {
        base.makeBody(configuration: configuration)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// 横幅を抑えた主要ボタン（行内・ヘッダー内の操作用。高さ 44pt）。
struct LiveOpsCompactButtonStyle: ButtonStyle {
    var color: Color = Theme.gold

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.heading(14))
            .foregroundStyle(Color.black.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: color.opacity(0.4), radius: configuration.isPressed ? 2 : 6)
            .contentShape(Capsule())
    }
}

/// タイル型のトグル（練習オプションなど、グリッドに並べる用）。
/// VoiceOver のスイッチ表現（オン/オフ）は Toggle 自体が提供する。
struct LiveOpsTileToggleStyle: ToggleStyle {
    var tint: Color = Theme.cyan

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            // 記号を上段、名前を下段の 1 行に置き、狭いタイルでも語の途中で折り返さないようにする
            configuration.label
                .labelStyle(LiveOpsTileLabelStyle())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(configuration.isOn ? tint : Theme.textSecondary.opacity(0.7))
                }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(configuration.isOn ? tint.opacity(0.16) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(configuration.isOn ? tint.opacity(0.8) : Theme.panelStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// タイル用のラベル（記号を上、名前を下に 1 行で）。
struct LiveOpsTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.icon
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.cyan)
            configuration.title
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 行全体をタップ可能にしたスイッチ（最小 44pt）。
struct LiveOpsToggleStyle: ToggleStyle {
    var tint: Color = Theme.cyan

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 10) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.16)))
                        .overlay(Capsule().stroke(Color.white.opacity(configuration.isOn ? 0.5 : 0.2), lineWidth: 1))
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(3)
                }
                .frame(width: 50, height: 30)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
