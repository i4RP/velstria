import SwiftUI

// 担当: online。フレンドの画面（シート）と、パーティの招待のダイアログ。ロジックは FriendHub。
// - 自分のフレンドコード（コピー・共有）/ コードで申請 / 届いた申請の承認 / フレンド一覧（在席・招待・削除）
// - 招待: 自分の部屋（パーティ）がなければ作ってから、部屋コードをフレンドの受信箱へ送る。受け取った側は 拒否 / 待って / 同意。
// - 招待のダイアログ（PartyInviteOverlay）はルートに重ねる。戦闘中は出さない（届いた時点で「試合中」と返す）。

struct FriendsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var removing: Friend?

    private var hub: FriendHub { app.friends }

    /// いま招待に使える部屋（自分がホストで中継が開いている、または部屋コードで入っている）。
    private var inviteRoom: (code: String, name: String)? {
        guard let session = app.online else { return nil }
        if session.isHost {
            guard let code = session.relayCode, session.relayStatus?.isReady == true else { return nil }
            return (code, session.room.name)
        }
        guard let code = session.joinedRelayCode, session.isConnected else { return nil }
        return (code, session.room.name)
    }

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 8) {
                header
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        VStack(spacing: 10) {
                            myCodePanel
                            addPanel
                            if !hub.incomingRequests.isEmpty { requestsPanel }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 290)
                    friendsPanel.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            // シートはルートの重ね表示より手前に出るので、招待のダイアログとトーストはここにも重ねる
            PartyInviteOverlay()
            ToastOverlay()
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(removing.map { L("\(FriendNames.display($0.name)) をフレンドから外しますか？", "Remove \(FriendNames.display($0.name)) from your friends?") } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button(L("フレンドから外す", "Remove"), role: .destructive) {
                if let f = removing { hub.removeFriend(code: f.code) }
                removing = nil
            }
            Button(L("キャンセル", "Cancel"), role: .cancel) { removing = nil }
        }
    }

    // MARK: ヘッダー

    private var header: some View {
        HStack(spacing: 10) {
            Text(L("フレンド", "Friends"))
                .font(Theme.title(22))
                .foregroundStyle(Theme.textPrimary)
            statusLabel
            Spacer()
            Button {
                FlowFX.back(app)
                dismiss()
            } label: {
                Text(L("閉じる", "Close"))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("friends_close")
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText)
                .font(Theme.body(11))
                .foregroundStyle(statusColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("friends_status")
    }

    private var statusColor: Color {
        switch hub.status {
        case .online: return Theme.success
        case .failed: return Theme.danger
        case .connecting, .offline: return Theme.textSecondary
        }
    }

    private var statusText: String {
        switch hub.status {
        case .online: return L("オンライン", "Online")
        case .connecting: return L("接続中…", "Connecting…")
        case .offline: return L("オフライン", "Offline")
        case .failed(let reason): return reason
        }
    }

    // MARK: 自分のコード

    private var myCodePanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("あなたのフレンドコード", "Your Friend Code"), systemImage: "person.crop.circle.badge.checkmark")
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Text(FriendCode.display(hub.myCode))
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.gold)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .accessibilityLabel(L("フレンドコード \(hub.myCode.map { String($0) }.joined(separator: " "))",
                                              "Friend code \(hub.myCode.map { String($0) }.joined(separator: " "))"))
                        .accessibilityIdentifier("friends_my_code")
                    Spacer(minLength: 0)
                    Button {
                        FlowFX.tap(app)
                        UIPasteboard.general.string = hub.myCode
                        app.showToast(L("フレンドコードをコピーしました", "Friend code copied"))
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("フレンドコードをコピー", "Copy friend code"))
                    .accessibilityIdentifier("friends_copy")
                    ShareLink(item: FriendLink.shareText(code: hub.myCode, name: hub.myName)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("フレンドコードを共有", "Share friend code"))
                    .accessibilityIdentifier("friends_share")
                }
                Text(L("コードかリンクを友達に送ると、友達がフレンド申請できます。", "Send your code or link to a friend so they can send you a request."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 追加

    private var parsedCode: Result<String, FriendCode.InputError> { FriendCode.parse(codeInput) }
    private var codeIsValid: Bool { if case .success = parsedCode { return true } else { return false } }
    private var codeHasError: Bool {
        switch parsedCode {
        case .failure(.ambiguous), .failure(.invalid), .failure(.tooLong): return true
        default: return false
        }
    }

    private var addPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("フレンドを追加", "Add a Friend"), systemImage: "person.badge.plus")
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    TextField("", text: $codeInput, prompt: Text("ABCD EFGH").foregroundStyle(Theme.textSecondary.opacity(0.5)))
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.gold)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.send)
                        .onSubmit { sendRequest() }
                        .onChange(of: codeInput) { _, v in
                            let cleaned = FriendCode.cleaned(v)
                            if cleaned != v { codeInput = cleaned }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.3)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(codeHasError ? Theme.danger : Theme.panelStroke, lineWidth: 1))
                        .accessibilityLabel(L("相手のフレンドコード", "Friend code"))
                        .accessibilityIdentifier("friends_code_field")
                    Button {
                        sendRequest()
                    } label: {
                        Text(L("申請", "Send"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .opacity(codeIsValid ? 1 : 0.5)
                    .accessibilityIdentifier("friends_send")
                }
                if codeHasError {
                    Text(codeHint)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var codeHint: String {
        if case .failure(let e) = parsedCode { return e.message }
        return ""
    }

    private func sendRequest() {
        switch hub.requestFriend(input: codeInput) {
        case .sent, .accepted:
            FlowFX.confirm(app)
            codeInput = ""
        case .alreadyFriend:
            FlowFX.error(app)
            app.showToast(L("すでにフレンドです", "You are already friends"))
        case .isSelf:
            FlowFX.error(app)
            app.showToast(L("自分のフレンドコードです", "That is your own friend code"))
        case .invalid(let message):
            FlowFX.error(app)
            app.showToast(message)
        }
    }

    // MARK: 届いた申請

    private var requestsPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("フレンド申請", "Friend Requests"), systemImage: "bell.badge.fill")
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.gold)
                ForEach(hub.incomingRequests) { request in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FriendNames.display(request.name)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text(FriendCode.display(request.code)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 4)
                        Button {
                            FlowFX.tap(app)
                            hub.ignore(request)
                        } label: {
                            Text(L("無視", "Ignore")).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("friends_ignore_\(request.code)")
                        Button {
                            FlowFX.confirm(app)
                            hub.approve(request)
                        } label: {
                            Text(L("承認", "Accept")).font(Theme.body(12)).foregroundStyle(Theme.gold)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("friends_approve_\(request.code)")
                    }
                }
            }
        }
    }

    // MARK: フレンド一覧

    private var friendsPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L("フレンド（\(hub.friends.count)）", "Friends (\(hub.friends.count))"), systemImage: "person.2.fill")
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if inviteRoom == nil {
                        Button {
                            FlowFX.confirm(app)
                            app.hostPartyRoom()
                        } label: {
                            Label(L("パーティを作る", "Create Party"), systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("friends_create_party")
                    } else {
                        Label(L("パーティに招待できます", "Ready to invite"), systemImage: "checkmark.circle.fill")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.success)
                    }
                }
                if hub.friends.isEmpty {
                    Text(L("まだフレンドがいません。フレンドコードを交換して申請しましょう。", "No friends yet. Exchange friend codes to send a request."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(sortedFriends) { friend in friendRow(friend) }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }

    /// オンラインの人を上に、その中は追加した順。
    private var sortedFriends: [Friend] {
        let all = hub.friends
        return all.filter { hub.isFriendOnline($0.code) } + all.filter { !hub.isFriendOnline($0.code) }
    }

    private func friendRow(_ friend: Friend) -> some View {
        let online = hub.isFriendOnline(friend.code)
        return HStack(spacing: 8) {
            Circle().fill(online ? Theme.success : Color.white.opacity(0.25)).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(FriendNames.display(friend.name)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(online ? L("オンライン", "Online") : L("オフライン", "Offline"))
                    .font(Theme.body(10))
                    .foregroundStyle(online ? Theme.success : Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Button {
                FlowFX.tap(app)
                removing = friend
            } label: {
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(FriendNames.display(friend.name)) をフレンドから外す", "Remove \(FriendNames.display(friend.name))"))
            .accessibilityIdentifier("friends_remove_\(friend.code)")
            Button {
                invite(friend)
            } label: {
                Text(L("招待", "Invite"))
                    .font(Theme.body(12))
                    .foregroundStyle(online ? Theme.gold : Theme.textSecondary.opacity(0.6))
                    .frame(minWidth: 52, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!online)
            .accessibilityLabel(L("\(FriendNames.display(friend.name)) をパーティに招待", "Invite \(FriendNames.display(friend.name)) to the party"))
            .accessibilityIdentifier("friends_invite_\(friend.code)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }

    /// 招待する。部屋がまだ無ければ作り、部屋コードが使えるようになるまで（最大 10 秒）待ってから送る。
    private func invite(_ friend: Friend) {
        FlowFX.confirm(app)
        if inviteRoom == nil { app.hostPartyRoom() }
        Task { @MainActor in
            for _ in 0..<40 {
                if let room = inviteRoom {
                    hub.invite(friend, roomCode: room.code, roomName: room.name)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            app.showToast(L("部屋の準備ができませんでした。もう一度お試しください", "The room is not ready. Please try again"))
        }
    }
}

// MARK: - パーティの招待のダイアログ

/// フレンドからパーティに招待された時のダイアログ（ルートに重ねる）: 拒否 / 待って（30 秒後に参加）/ 同意。
struct PartyInviteOverlay: View {
    @Environment(AppModel.self) private var app
    @State private var suppress = false

    var body: some View {
        if let invite = app.friends.pendingInvite, app.activeBattle == nil, app.activeMagicChess == nil {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 10) {
                    Text(L("フレンドより", "From a Friend"))
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.gold)
                    Text(invite.name)
                        .font(Theme.heading(18))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .accessibilityIdentifier("invite_name")
                    Text(L("パーティに招待されました。", "You have been invited to a party."))
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                    if !invite.roomName.isEmpty {
                        Text(invite.roomName)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        Button {
                            FlowFX.back(app)
                            respond(.decline(suppress: suppress))
                        } label: {
                            Text(L("拒否", "Decline")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("invite_decline")
                        Button {
                            FlowFX.tap(app)
                            respond(.wait)
                        } label: {
                            VStack(spacing: 0) {
                                Text(L("待って！", "Wait!"))
                                Text(L("\(FriendHub.waitSeconds)秒後に参加", "Join in \(FriendHub.waitSeconds)s")).font(Theme.body(10))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("invite_wait")
                        Button {
                            FlowFX.confirm(app)
                            respond(.accept)
                        } label: {
                            Text(L("同意", "Accept")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("invite_accept")
                    }
                    Button {
                        FlowFX.tap(app)
                        suppress.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: suppress ? "checkmark.square.fill" : "square")
                                .foregroundStyle(suppress ? Theme.cyan : Theme.textSecondary)
                            Text(L("5分間、このプレイヤーの招待を拒否する", "Decline invites from this player for 5 minutes"))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(suppress ? .isSelected : [])
                    .accessibilityIdentifier("invite_suppress")
                }
                .padding(20)
                .frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.gold.opacity(0.6), lineWidth: 1))
            }
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func respond(_ response: FriendHub.InviteResponse) {
        suppress = false
        app.friends.respond(response)
    }
}
