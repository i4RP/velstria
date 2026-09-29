import SwiftUI
import UIKit
import VelstriaCore

// 担当: ui-liveops。UI067 サポート / UI069 お問い合わせ（mailto: + 端末情報、メール不可時はコピー）。

// MARK: - お問い合わせの組み立て

enum SupportCategory: String, CaseIterable, Identifiable {
    case bug, purchase, account, feedback, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return L("不具合の報告", "Bug Report")
        case .purchase: return L("購入・課金", "Purchases")
        case .account: return L("データ・引き継ぎ", "Data & Transfer")
        case .feedback: return L("ご意見・ご要望", "Feedback")
        case .other: return L("その他", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .bug: return "ladybug.fill"
        case .purchase: return "creditcard.fill"
        case .account: return "arrow.triangle.2.circlepath"
        case .feedback: return "lightbulb.fill"
        case .other: return "ellipsis.bubble.fill"
        }
    }

    /// 件名の分類タグ（サポート側の仕分け用に言語によらず固定）。
    var subjectTag: String {
        switch self {
        case .bug: return "Bug"
        case .purchase: return "Purchase"
        case .account: return "Data"
        case .feedback: return "Feedback"
        case .other: return "Other"
        }
    }

    var placeholder: String {
        switch self {
        case .bug: return L("発生した画面・操作・頻度をできるだけ詳しくお書きください。", "Describe the screen, what you did and how often it happens.")
        case .purchase: return L("購入日時・商品名・Apple のレシートの注文番号をお書きください。", "Include the purchase date, product and the order ID from Apple's receipt.")
        case .account: return L("お困りの状況（機種変更・バックアップなど）をお書きください。", "Describe your situation (new device, backup, etc.).")
        case .feedback: return L("ご意見・ご要望をお聞かせください。", "Tell us what you think.")
        case .other: return L("お問い合わせ内容をお書きください。", "Write your message.")
        }
    }
}

/// お問い合わせに添える端末情報。
struct SupportDeviceInfo: Equatable {
    var appVersion: String
    var build: String
    var device: String
    var os: String
    var playerID: String
    var language: String

    static func current(profile: Profile) -> SupportDeviceInfo {
        SupportDeviceInfo(appVersion: AppVersionInfo.version, build: AppVersionInfo.build, device: AppVersionInfo.deviceModel,
                          os: AppVersionInfo.systemVersion, playerID: profile.playerID, language: Loc.current.rawValue)
    }

    var lines: [String] {
        ["App: VELSTRIA \(appVersion) (\(build))", "Device: \(device)", "OS: \(os)", "Player ID: \(playerID)", "Language: \(language)"]
    }
}

enum SupportMail {
    static let maxLength = 2000

    static func subject(_ category: SupportCategory) -> String {
        "[VELSTRIA] \(category.subjectTag)"
    }

    static func body(message: String, info: SupportDeviceInfo) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([trimmed, "", "---"] + info.lines).joined(separator: "\n")
    }

    /// mailto: URL。件名・本文は RFC 6068 に従い非予約文字以外をすべてパーセントエンコードする。
    static func url(to address: String = FeatureFlags.supportEmail, category: SupportCategory, message: String,
                    info: SupportDeviceInfo) -> URL? {
        let query = "subject=\(encode(subject(category)))&body=\(encode(body(message: message, info: info)))"
        return URL(string: "mailto:\(address)?\(query)")
    }

    static func encode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

// MARK: - UI067 サポート

struct SupportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScreenScaffold(title: L("サポート", "Support"), showsCurrencies: false) {
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        SettingsHubTile(title: L("よくある質問", "FAQ"), summary: L("操作・購入・データ", "Controls, purchases, data"),
                                        symbol: "questionmark.bubble.fill", identifier: "support_faq") { push(.faq) }
                        SettingsHubTile(title: L("お問い合わせ", "Contact Us"), summary: L("メールで相談", "Email support"),
                                        symbol: "envelope.fill", identifier: "support_contact") { push(.contact) }
                        SettingsHubTile(title: L("パッチノート", "Patch Notes"), summary: "v\(AppVersionInfo.version)",
                                        symbol: "doc.text.fill", identifier: "support_patch_notes") { push(.patchNotes) }
                        SettingsHubTile(title: L("利用規約", "Terms of Service"), summary: L("ブラウザで開く", "Opens in browser"),
                                        symbol: "doc.plaintext.fill", external: true, identifier: "support_terms") {
                            openURL(FeatureFlags.termsURL)
                        }
                        SettingsHubTile(title: L("プライバシーポリシー", "Privacy Policy"), summary: L("ブラウザで開く", "Opens in browser"),
                                        symbol: "lock.shield.fill", external: true, identifier: "support_privacy") {
                            openURL(FeatureFlags.privacyPolicyURL)
                        }
                        SettingsHubTile(title: L("クレジット", "Credits"), summary: L("制作チーム", "The team"),
                                        symbol: "star.fill", tint: Theme.gold, identifier: "support_credits") { push(.credits) }
                        SettingsHubTile(title: L("チュートリアル", "Tutorial"), summary: L("基本操作とヒント集", "Basics and tips"),
                                        symbol: "graduationcap.fill", tint: Theme.gold, identifier: "support_tutorial") { push(.tutorialMenu) }
                    }
                    .frame(maxWidth: .infinity)
                    infoPanel
                        .frame(width: 260)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
    }

    private func push(_ route: Route) {
        app.audio.play(.uiTap)
        app.router.push(route)
    }

    private var infoPanel: some View {
        SettingsSection(title: L("アプリ情報", "App Info"), symbol: "info.circle.fill") {
            infoRow(L("バージョン", "Version"), AppVersionInfo.version)
            infoRow(L("ビルド", "Build"), AppVersionInfo.build)
            infoRow(L("機種", "Device"), AppVersionInfo.deviceModel)
            infoRow("OS", AppVersionInfo.systemVersion)
            SettingsDivider()
            VStack(alignment: .leading, spacing: 4) {
                Text(L("プレイヤー ID（お問い合わせ時にお伝えください）", "Player ID (include it when contacting us)"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(app.profile.playerID)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    LiveOpsIconButton(symbol: "doc.on.doc", label: L("プレイヤー ID をコピー", "Copy Player ID"), tint: Theme.cyan,
                                      identifier: "support_copy_player_id") {
                        UIPasteboard.general.string = app.profile.playerID
                        app.haptics.tap()
                        app.showToast(L("プレイヤー ID をコピーしました", "Player ID copied"))
                    }
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(Theme.body(12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - UI069 お問い合わせ

struct ContactView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var category: SupportCategory = .bug
    @State private var message = ""
    @State private var showsFallback = false
    @FocusState private var editorFocused: Bool

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScreenScaffold(title: L("お問い合わせ", "Contact Us"), showsCurrencies: false) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView(.vertical, showsIndicators: false) {
                    Panel(padding: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            LiveOpsSectionHeader(title: L("カテゴリ", "Category"), symbol: "tag.fill")
                            LiveOpsSegmented(options: SupportCategory.allCases.map {
                                LiveOpsSegmentOption(value: $0, title: $0.title, symbol: $0.symbol, identifier: "contact_category_\($0.rawValue)")
                            }, selection: $category, axis: .vertical, onChange: { _ in app.audio.play(.uiTap) })
                        }
                    }
                }
                .frame(width: 210)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 10) {
                        editorPanel
                        fallbackPanel
                    }
                    .padding(.bottom, 10)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var editorPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    LiveOpsSectionHeader(title: L("お問い合わせ内容", "Message"), symbol: "square.and.pencil")
                    Spacer()
                    Text("\(message.count) / \(SupportMail.maxLength)")
                        .font(Theme.mono(11))
                        .foregroundStyle(message.count > SupportMail.maxLength ? Theme.danger : Theme.textSecondary)
                        .monospacedDigit()
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $message)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                        .frame(minHeight: 110, maxHeight: 150)
                        .accessibilityLabel(L("お問い合わせ内容", "Message"))
                        .accessibilityIdentifier("contact_message")
                        .onChange(of: message) { _, newValue in
                            if newValue.count > SupportMail.maxLength { message = String(newValue.prefix(SupportMail.maxLength)) }
                        }
                    if message.isEmpty {
                        Text(category.placeholder)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(editorFocused ? Theme.cyan : Theme.panelStroke, lineWidth: 1))
                Text(L("送信するとメールアプリが開きます。アプリのバージョン・機種・OS・プレイヤー ID が本文に自動で添付されます。",
                       "Sending opens your mail app. App version, device, OS and Player ID are appended automatically."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if editorFocused {
                        Button {
                            editorFocused = false
                        } label: {
                            Label(L("キーボードを閉じる", "Hide Keyboard"), systemImage: "keyboard.chevron.compact.down")
                                .lineLimit(1)
                        }
                        .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                    }
                    Spacer()
                    Button {
                        send()
                    } label: {
                        Label(L("メールで送信", "Send by Email"), systemImage: "paperplane.fill").lineLimit(1)
                    }
                    .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                    .disabled(trimmedMessage.isEmpty)
                    .opacity(trimmedMessage.isEmpty ? 0.45 : 1)
                    .accessibilityIdentifier("contact_send")
                }
            }
        }
    }

    private var fallbackPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label(showsFallback ? L("メールアプリを開けませんでした", "Couldn't open a mail app")
                                    : L("メールアプリを使えない場合", "If you can't use a mail app"),
                      systemImage: showsFallback ? "exclamationmark.triangle.fill" : "envelope.open.fill")
                    .font(Theme.heading(13))
                    .foregroundStyle(showsFallback ? Theme.gold : Theme.textPrimary)
                Text(L("下記アドレス宛てに、コピーした本文を貼り付けて送信してください。",
                       "Send the copied message to the address below from any email service."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(FeatureFlags.supportEmail)
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button {
                        UIPasteboard.general.string = FeatureFlags.supportEmail
                        app.haptics.tap()
                        app.showToast(L("メールアドレスをコピーしました", "Email address copied"))
                    } label: {
                        Label(L("アドレス", "Address"), systemImage: "doc.on.doc").lineLimit(1)
                    }
                    .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                    .accessibilityLabel(L("メールアドレスをコピー", "Copy email address"))
                    .accessibilityIdentifier("contact_copy_email")
                    Button {
                        UIPasteboard.general.string = "\(SupportMail.subject(category))\n\n" +
                            SupportMail.body(message: message, info: SupportDeviceInfo.current(profile: app.profile))
                        app.haptics.tap()
                        app.showToast(L("本文をコピーしました", "Message copied"))
                    } label: {
                        Label(L("本文", "Message"), systemImage: "doc.on.clipboard").lineLimit(1)
                    }
                    .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                    .accessibilityLabel(L("本文をコピー", "Copy message"))
                    .accessibilityIdentifier("contact_copy_body")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(showsFallback ? Theme.gold.opacity(0.7) : .clear, lineWidth: 1))
    }

    private func send() {
        guard !trimmedMessage.isEmpty else { return }
        editorFocused = false
        guard let url = SupportMail.url(category: category, message: message, info: SupportDeviceInfo.current(profile: app.profile)) else {
            showsFallback = true
            return
        }
        app.audio.play(.uiConfirm)
        openURL(url) { accepted in
            if !accepted {
                app.audio.play(.uiError)
                withAnimation { showsFallback = true }
            }
        }
    }
}
