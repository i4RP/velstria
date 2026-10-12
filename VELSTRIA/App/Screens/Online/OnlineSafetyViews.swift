import SwiftUI

// 担当: online。オンライン機能の安全対策の画面（App Review Guidelines 1.2 / 5.1）。ロジックは Online/OnlineSafety.swift。
// - OnlineRulesConsentView: 初めてオンラインを開いた時の同意（コミュニティガイドライン・利用規約。迷惑行為を容認しない旨）。
// - OnlineUnavailableView: 13 歳未満と申告した人には使えないことを知らせる。
// - PlayerActionsMenu: 他のプレイヤーへの「通報」「ブロック」「部屋から外す（ホスト）」。
// - PlayerReportSheet: 運営宛ての通報メールの下書き（相手の表示名・フレンドコードなど入り）。送る時にブロックもできる。

// MARK: - 同意

struct OnlineRulesConsentView: View {
    @Environment(AppModel.self) private var app
    @State private var agreed = false

    private struct Rule: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let body: String
    }

    static var rules: [(symbol: String, title: String, body: String)] {
        [
            ("hand.raised.fill", L("迷惑行為は一切容認しません", "Zero tolerance for abuse"),
             L("不快・差別的・性的な表示名、嫌がらせ、なりすまし、チートや改造したアプリ、しつこい申請や招待など、不適切なコンテンツや迷惑行為は一切容認しません。違反を確認したプレイヤーは、オンライン機能の利用を制限することがあります。",
               "We do not tolerate objectionable content or abusive users: offensive, hateful or sexual names, harassment, impersonation, cheating or modified apps, and spamming requests or invites. Players who break these rules may lose access to online features.")),
            ("person.2.fill", L("ほかのプレイヤーに見えるもの", "What other players see"),
             L("表示名・アイコン・フレンドコード・選んだヒーローなどが、同じ部屋の参加者と観戦者、フレンドに表示されます。同じ Wi-Fi では部屋名（あなたの表示名を含む）が近くの端末にも表示され、そのネットワークの誰でも参加・観戦できます。本名や連絡先を名前に使わないでください。自由入力のチャットはありません。",
               "Your name, icon, friend code and chosen hero are shown to players and spectators in the same room and to your friends. On the same Wi-Fi, your room name (which includes your name) is visible to nearby devices, and anyone on that network can join or watch. Don't use your real name or contact details. There is no free-text chat.")),
            ("exclamationmark.bubble.fill", L("通報・ブロック", "Report and block"),
             L("迷惑なプレイヤーは、パーティの枠・参加者の一覧・フレンド・申請や招待の画面・試合結果から「通報」「ブロック」できます。ホストは参加者を部屋から外せます。通報は運営（\(FeatureFlags.supportEmail)）が確認し、利用規約とコミュニティガイドラインに沿って対応します。身の危険を感じたら、すぐに警察などに相談してください。",
               "You can report or block players from party slots, the member list, friends, requests and invites, and match results. Hosts can remove players from their room. Reports go to us (\(FeatureFlags.supportEmail)); we review them and act under the Terms and Community Guidelines. If you feel unsafe, contact the police or other authorities right away.")),
            ("lock.shield.fill", L("データの取り扱い", "Your data"), OnlineRelayConfig.privacyNote),
        ]
    }

    private var sections: [Rule] {
        Self.rules.enumerated().map { Rule(id: $0.offset, symbol: $0.element.symbol, title: $0.element.title, body: $0.element.body) }
    }

    var body: some View {
        ScreenScaffold(title: L("オンライン", "Online"), showsCurrencies: false) {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sections) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(s.title, systemImage: s.symbol)
                                    .font(Theme.heading(15))
                                    .foregroundStyle(Theme.gold)
                                Text(s.body)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .glass(cornerRadius: 16)
                .accessibilityIdentifier("online_rules_scroll")

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("オンラインのルール", "Online Rules"))
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("オンライン対戦・フレンドを使う前に、ルールを確認して同意してください。",
                           "Before using online matches and friends, please review and accept the rules."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    OnlineLegalLinks()
                    Button {
                        FlowFX.tap(app)
                        withAnimation(.spring(duration: 0.25)) { agreed.toggle() }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(agreed ? Theme.gold : Theme.textSecondary)
                            Text(L("コミュニティガイドラインと利用規約に同意します", "I agree to the Community Guidelines and Terms of Service"))
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(agreed ? .isSelected : [])
                    .accessibilityIdentifier("online_rules_agree")
                    Button {
                        FlowFX.confirm(app)
                        app.acceptOnlineRules()
                    } label: {
                        Text(L("同意してはじめる", "Agree and Continue")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!agreed)
                    .opacity(agreed ? 1 : 0.5)
                    .accessibilityIdentifier("online_rules_accept")
                }
                .frame(width: 280)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }
}

/// コミュニティガイドライン・通報とブロック・利用規約・プライバシーポリシー・外部送信へのリンク（ブラウザで開く）。
struct OnlineLegalLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            link(L("コミュニティガイドライン", "Community Guidelines"), symbol: "person.3.sequence.fill",
                 url: FeatureFlags.communityGuidelinesURL, identifier: "online_rules_guidelines")
            link(L("通報とブロック", "Reporting and Blocking"), symbol: "exclamationmark.shield.fill",
                 url: FeatureFlags.safetyURL, identifier: "online_rules_safety")
            link(L("利用規約", "Terms of Service"), symbol: "doc.text.fill", url: FeatureFlags.termsURL, identifier: "online_rules_terms")
            link(L("プライバシーポリシー", "Privacy Policy"), symbol: "hand.raised.square.fill",
                 url: FeatureFlags.privacyPolicyURL, identifier: "online_rules_privacy")
            link(L("外部送信について", "External Transmission"), symbol: "arrow.up.forward.app.fill",
                 url: FeatureFlags.externalTransmissionURL, identifier: "online_rules_external")
        }
    }

    private func link(_ title: String, symbol: String, url: URL, identifier: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Theme.cyan).frame(width: 20)
                Text(title).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square").foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }
}

/// オンライン機能を使えない（13 歳未満）。
struct OnlineUnavailableView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("オンライン", "Online"), showsCurrencies: false) {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
                Text(OnlineAccess.ageRestrictedMessage)
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Text(L("ひとりで遊ぶモード（AI 対戦・ライジング・観戦・リプレイなど）はこれまでどおり遊べます。",
                       "All single-player modes (vs AI, Rising, spectating, replays and more) remain available."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Button {
                    FlowFX.back(app)
                    app.router.pop()
                } label: {
                    Text(L("戻る", "Back")).frame(minWidth: 140)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("online_unavailable_back")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("online_unavailable")
        }
    }
}

// MARK: - 通報・ブロックの操作

/// 他のプレイヤーへの操作の確認と通報の画面（画面ごとに 1 つ持ち、moderationPrompts で表示する）。
@Observable
@MainActor
final class ModerationPrompt {
    enum Confirm: Equatable {
        case block(PlayerReportTarget)
        case kick(PlayerReportTarget)

        var target: PlayerReportTarget {
            switch self {
            case .block(let t), .kick(let t): return t
            }
        }
    }

    /// 通報の画面を出している相手。
    var report: PlayerReportTarget?
    /// 確認を出している操作。
    var confirm: Confirm?
}

private struct ModerationPromptsModifier: ViewModifier {
    @Bindable var prompt: ModerationPrompt
    @Environment(AppModel.self) private var app

    private var title: String {
        switch prompt.confirm {
        case .block(let t)?: return L("\(t.displayName) をブロックしますか？", "Block \(t.displayName)?")
        case .kick(let t)?: return L("\(t.displayName) を部屋から外しますか？", "Remove \(t.displayName) from the room?")
        case nil: return ""
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $prompt.report) { target in
                PlayerReportSheet(target: target).environment(app)
            }
            .confirmationDialog(title, isPresented: Binding(get: { prompt.confirm != nil }, set: { if !$0 { prompt.confirm = nil } }),
                                titleVisibility: .visible, presenting: prompt.confirm) { confirm in
                switch confirm {
                case .block(let t):
                    Button(L("ブロックする", "Block"), role: .destructive) {
                        FlowFX.confirm(app)
                        app.blockPlayer(t)
                    }
                case .kick(let t):
                    Button(L("部屋から外す", "Remove"), role: .destructive) {
                        FlowFX.confirm(app)
                        app.kickFromRoom(t)
                    }
                }
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            } message: { confirm in
                switch confirm {
                case .block:
                    Text(L("この相手からのフレンド申請・招待が届かなくなり、あなたの部屋に入れなくなります。フレンドからも外れます。相手には知らされません。設定 > プライバシー で解除できます。",
                           "You will no longer get friend requests or invites from this player, and they can't join your room. They are also removed from your friends and are not notified. Unblock any time in Settings > Privacy."))
                case .kick:
                    Text(L("この部屋には入り直せなくなります。試合中なら、その人のヒーローは AI が引き継ぎます。",
                           "They can't rejoin this room. During a match, AI takes over their hero."))
                }
            }
    }
}

extension View {
    /// 通報の画面と、ブロック・部屋から外す の確認を付ける。
    func moderationPrompts(_ prompt: ModerationPrompt) -> some View {
        modifier(ModerationPromptsModifier(prompt: prompt))
    }
}

/// 他のプレイヤーへの操作のメニュー（通報 / ブロック・解除 / 部屋から外す）。
struct PlayerActionsMenu: View {
    let target: PlayerReportTarget
    let prompt: ModerationPrompt
    /// 自分がホストで、相手が部屋にいる。
    var canKick = false
    var size: CGFloat = 18
    @Environment(AppModel.self) private var app

    /// メニューに出す名前（ブロック中の相手は名前を出さない。通報のメールの本文には本当の名前が入る）。
    private var shownName: String {
        if let code = target.friendCode, app.friends.isBlocked(code) { return PlayerReportTarget.blockedName }
        return target.displayName
    }

    var body: some View {
        Menu {
            Section(shownName) {
                Button {
                    prompt.report = target
                } label: {
                    Label(L("通報する", "Report"), systemImage: "exclamationmark.bubble")
                }
                if let code = target.friendCode {
                    if app.friends.isBlocked(code) {
                        Button {
                            app.friends.unblock(code: code)
                            app.showToast(L("ブロックを解除しました", "Unblocked"))
                        } label: {
                            Label(L("ブロックを解除", "Unblock"), systemImage: "hand.raised.slash")
                        }
                    } else {
                        Button(role: .destructive) {
                            prompt.confirm = .block(target)
                        } label: {
                            Label(L("ブロックする", "Block"), systemImage: "hand.raised.fill")
                        }
                    }
                }
                if canKick {
                    Button(role: .destructive) {
                        prompt.confirm = .kick(target)
                    } label: {
                        Label(L("部屋から外す", "Remove from Room"), systemImage: "person.fill.xmark")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("\(shownName) の通報・ブロック", "Report or block \(shownName)"))
        .accessibilityIdentifier("player_actions_\(target.peerID ?? target.friendCode ?? target.name)")
    }
}

// MARK: - 通報の画面

struct PlayerReportSheet: View {
    let target: PlayerReportTarget
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reason: PlayerReportReason = .inappropriateName
    @State private var message = ""
    @State private var alsoBlock = true
    @State private var mailFailed = false
    @State private var prepared = false

    private var canBlock: Bool { target.friendCode != nil && !(target.friendCode.map(app.friends.isBlocked) ?? false) }
    /// 見出しの名前（ブロック中の相手は名前を出さない）。
    private var shownName: String {
        target.friendCode.map(app.friends.isBlocked) == true ? PlayerReportTarget.blockedName : target.displayName
    }

    private var mailBody: String {
        PlayerReportMail.body(target: target, reason: reason, message: message, reporterCode: app.profile.friendCode,
                              date: Date(), appVersion: ReportMail.appVersion, systemVersion: UIDevice.current.systemVersion)
    }

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Label(L("プレイヤーを通報", "Report a Player"), systemImage: "exclamationmark.bubble.fill")
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(shownName).font(Theme.heading(14)).foregroundStyle(Theme.gold).lineLimit(1)
                        if let code = target.friendCode {
                            Text(FriendCode.display(code)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    FlowCloseButton(identifier: "player_report_close") { dismiss() }
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        FlowSectionTitle(title: L("理由", "Reason"))
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(PlayerReportReason.allCases) { r in reasonButton(r) }
                            }
                        }
                    }
                    .frame(width: 210)

                    VStack(alignment: .leading, spacing: 8) {
                        FlowSectionTitle(title: L("内容（任意）", "Details (optional)"), trailing: "\(message.count)/\(PlayerReportMail.maxLength)")
                        TextEditor(text: $message)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 70)
                            .glass(cornerRadius: 12)
                            .overlay(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text(L("いつ・どこで・何があったか", "When, where and what happened"))
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(14)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onChange(of: message) { _, v in
                                if v.count > PlayerReportMail.maxLength { message = String(v.prefix(PlayerReportMail.maxLength)) }
                            }
                            .accessibilityIdentifier("player_report_text")
                        if canBlock {
                            Button {
                                FlowFX.tap(app)
                                alsoBlock.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: alsoBlock ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(alsoBlock ? Theme.cyan : Theme.textSecondary)
                                    Text(L("このプレイヤーをブロックする", "Also block this player"))
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                .frame(minHeight: 36)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(alsoBlock ? .isSelected : [])
                            .accessibilityIdentifier("player_report_block")
                        }
                        Text(L("メールアプリで \(FeatureFlags.supportEmail) 宛の下書きを作ります。相手の表示名・フレンドコード・プレイヤー ID、出会った場所と部屋コード、あなたのフレンドコード、アプリの版が入ります。運営が内容を確認し、利用規約とコミュニティガイドラインに沿って対応します。",
                               "This opens a draft to \(FeatureFlags.supportEmail) in Mail with the player's name, friend code and player ID, where you met and the room code, your friend code, and the app version. We review every report and act under the Terms and Community Guidelines."))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Link(destination: FeatureFlags.communityGuidelinesURL) {
                                Label(L("コミュニティガイドライン", "Community Guidelines"), systemImage: "arrow.up.right.square")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.cyan)
                                    .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("player_report_guidelines")
                            Spacer()
                            Button(action: send) {
                                Label(L("メールで送信", "Send via Mail"), systemImage: "paperplane.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("player_report_send")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            ToastOverlay()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !prepared else { return }
            prepared = true
            alsoBlock = canBlock
        }
        .alert(L("メールアプリを開けませんでした", "Couldn't Open Mail"), isPresented: $mailFailed) {
            Button(L("内容をコピー", "Copy Report")) {
                UIPasteboard.general.string = "To: \(FeatureFlags.supportEmail)\n\(PlayerReportMail.subject(reason))\n\n\(mailBody)"
                app.showToast(L("コピーしました", "Copied"))
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("\(FeatureFlags.supportEmail) 宛に内容を送ってください。", "Please send the report to \(FeatureFlags.supportEmail)."))
        }
    }

    private func reasonButton(_ r: PlayerReportReason) -> some View {
        Button {
            FlowFX.tap(app)
            reason = r
        } label: {
            HStack(spacing: 8) {
                Image(systemName: r.symbol).frame(width: 20)
                Text(r.title).font(Theme.heading(12)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if reason == r { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
            }
            .foregroundStyle(reason == r ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(reason == r ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Color.white.opacity(0.07))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(reason == r ? .isSelected : [])
        .accessibilityIdentifier("player_report_reason_\(r.rawValue)")
    }

    private func send() {
        // ブロックはメールの成否によらず、送る操作をした時点で行う
        if alsoBlock && canBlock { app.blockPlayer(target) }
        guard let url = PlayerReportMail.url(subject: PlayerReportMail.subject(reason), body: mailBody) else {
            mailFailed = true
            return
        }
        FlowFX.confirm(app)
        openURL(url) { accepted in
            if accepted {
                app.showToast(L("ご報告ありがとうございます。運営が確認します", "Thanks for your report. We'll review it"))
                dismiss()
            } else {
                mailFailed = true
            }
        }
    }
}
