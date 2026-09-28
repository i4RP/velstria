import SwiftUI
import UIKit
import VelstriaCore

// 担当: ui-liveops。設定・サポート画面で共有する部品と表示文字列。

/// `app.profile.settings` の項目への Binding（変更は AppModel.profile の didSet で自動保存・反映される）。
@MainActor
func settingsBinding<T>(_ app: AppModel, _ keyPath: WritableKeyPath<GameSettings, T>) -> Binding<T> {
    Binding(get: { app.profile.settings[keyPath: keyPath] },
            set: { app.profile.settings[keyPath: keyPath] = $0 })
}

/// 設定値の表示名。
enum SettingsText {
    static func joystick(_ m: JoystickMode) -> String {
        switch m {
        case .fixed: return L("固定", "Fixed")
        case .floating: return L("フローティング", "Floating")
        }
    }

    static func joystickDetail(_ m: JoystickMode) -> String {
        switch m {
        case .fixed: return L("スティックを画面の定位置に表示します。", "The stick stays in a fixed position.")
        case .floating: return L("触れた位置にスティックが現れます。", "The stick appears where you touch.")
        }
    }

    static func castMode(_ m: SkillCastMode) -> String {
        switch m {
        case .smart: return L("スマート", "Smart")
        case .manual: return L("マニュアル", "Manual")
        }
    }

    static func castModeDetail(_ m: SkillCastMode) -> String {
        switch m {
        case .smart: return L("タップで自動照準して発動、ドラッグで手動照準。", "Tap to auto-aim and cast, drag to aim manually.")
        case .manual: return L("常にドラッグで狙いを定め、指を離して発動。", "Always drag to aim, release to cast.")
        }
    }

    static func attackPriority(_ p: TargetPriority) -> String {
        switch p {
        case .heroesFirst: return L("ヒーロー", "Heroes")
        case .minionsFirst: return L("ミニオン", "Minions")
        case .structuresFirst: return L("建物", "Structures")
        case .lowestHealth: return L("低HP", "Low HP")
        }
    }

    static func attackPriorityDetail(_ p: TargetPriority) -> String {
        switch p {
        case .heroesFirst: return L("射程内の敵ヒーローを優先して攻撃します。", "Attacks enemy heroes in range first.")
        case .minionsFirst: return L("ミニオン・モンスターを優先し、ラストヒットを取りやすくします。", "Prioritises minions and monsters for easier last hits.")
        case .structuresFirst: return L("タワー・Star Core を優先して攻撃します。", "Attacks towers and the Star Core first.")
        case .lowestHealth: return L("射程内で HP が最も低い敵を優先します。", "Targets the enemy with the lowest HP in range.")
        }
    }

    static let allPriorities: [TargetPriority] = [.heroesFirst, .minionsFirst, .structuresFirst, .lowestHealth]

    static func quality(_ q: GraphicsQuality) -> String {
        switch q {
        case .low: return L("低", "Low")
        case .medium: return L("中", "Medium")
        case .high: return L("高", "High")
        }
    }

    static func qualityDetail(_ q: GraphicsQuality) -> String {
        switch q {
        case .low: return L("影と演出を抑え、発熱と電池消費を軽減します。", "Reduces shadows and effects to save battery and heat.")
        case .medium: return L("画質と快適さのバランスを取った推奨設定です。", "Recommended balance of visuals and performance.")
        case .high: return L("高品質な影と演出。発熱と電池消費が増えます。", "High-quality shadows and effects. Uses more battery.")
        }
    }

    static func frameRate(_ f: FrameRateOption) -> String { "\(f.rawValue) FPS" }

    static func frameRateDetail(_ f: FrameRateOption) -> String {
        switch f {
        case .fps30: return L("電池の持ちを優先します。", "Prioritises battery life.")
        case .fps60: return L("なめらかな描画で操作しやすくなります。", "Smoother visuals and more responsive controls.")
        }
    }

    /// 言語名（各言語の自称表記。システムは現在の言語で表示）。
    static func language(_ l: AppLanguage) -> String {
        switch l {
        case .system: return L("システム設定", "System")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }

    static func onOff(_ on: Bool) -> String { on ? L("オン", "On") : L("オフ", "Off") }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

enum SettingsDefaults {
    /// 設定を初期値に戻す（言語と通知は端末の権限・好みに紐づくため維持する）。
    static func reset(_ current: GameSettings) -> GameSettings {
        var d = GameSettings()
        d.language = current.language
        d.notificationsEnabled = current.notificationsEnabled
        return d
    }
}

/// アプリのバージョン・端末情報（サポート・お問い合わせ用）。
enum AppVersionInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }
    static var display: String { "\(version) (\(build))" }

    /// 機種識別子（例: iPhone17,3）。シミュレータでは模擬している機種。
    static var deviceModel: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let id = mirror.children.reduce(into: "") { acc, child in
            if let v = child.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(bitPattern: v)))) }
        }
        return id.isEmpty ? "iPhone" : id
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

// MARK: - 部品

/// 設定のセクション（見出し + 行）。
struct SettingsSection<Content: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                LiveOpsSectionHeader(title: title, symbol: symbol)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 行ラベル（記号 + 見出し + 補足）。
struct SettingsRowLabel: View {
    let title: String
    var detail: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 22)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    @Binding var isOn: Bool
    let identifier: String

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: title, detail: detail, symbol: symbol)
        }
        .toggleStyle(LiveOpsToggleStyle())
        .accessibilityIdentifier(identifier)
    }
}

struct SettingsChoiceRow<Value: Hashable>: View {
    let title: String
    var detail: String?
    var symbol: String?
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    let identifier: String
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsRowLabel(title: title, detail: detail, symbol: symbol)
            LiveOpsSegmented(options: options.enumerated().map { i, o in
                LiveOpsSegmentOption(value: o.value, title: o.title, identifier: "\(identifier)_\(i)")
            }, selection: $selection, onChange: { _ in app.audio.play(.uiTap) })
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsSliderRow: View {
    let title: String
    var symbol: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    let format: (Double) -> String
    let identifier: String
    /// ドラッグ終了時（試聴などに使う）。
    var onCommit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SettingsRowLabel(title: title, symbol: symbol)
                Spacer()
                Text(format(value))
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step) { editing in
                if !editing { onCommit?() }
            }
            .tint(Theme.cyan)
            .frame(minHeight: 44)
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
            .accessibilityIdentifier(identifier)
        }
        .padding(.top, 4)
    }
}

/// 押すと遷移・外部リンクを開く行。
struct SettingsLinkRow: View {
    let title: String
    var detail: String?
    let symbol: String
    var external = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsRowLabel(title: title, detail: detail, symbol: symbol)
                Spacer(minLength: 4)
                Image(systemName: external ? "arrow.up.right.square" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// ハブ画面のタイル。
struct SettingsHubTile: View {
    let title: String
    let summary: String
    let symbol: String
    var tint: Color = Theme.cyan
    var external = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(summary)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                Image(systemName: external ? "arrow.up.right.square" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(summary)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// 区切り線。
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
}
