import SwiftUI

// 担当: online。フレンドの画面（シート）と、パーティの招待のダイアログ。ロジックは FriendHub。
// - フレンドの画面は PartySidePanel（パーティの右パネル）と同じ部品（フレンド・申請・最近一緒に遊んだ人・近くの部屋・部屋コード）
// - 招待: 自分の部屋（パーティ）がなければ作ってから、部屋コードをフレンドの受信箱へ送る。受け取った側は 拒否 / 待って / 同意。
// - 招待のダイアログ（PartyInviteOverlay）はルートに重ねる。戦闘中は出さない（届いた時点で「試合中」と返す）。
// - フレンド・届いた申請・招待から 通報・ブロック できる（ガイドライン 1.2。OnlineSafetyViews）。

/// フレンドの画面（部屋の画面の「招待」から開くシート）。パーティの右パネル（PartySidePanel）と同じ部品を使い、
/// フレンドの画面を 1 つにまとめる（第0段の「フレンドの画面が 3 つ」の統合。docs/OUTGAME_GAP.md 9-7）。
/// フレンド・申請・最近一緒に遊んだ人・近くの部屋・部屋コードのタブ、自分のコード・申請の入力は申請のタブ。
struct FriendsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var tab: PartySideTab = .friends

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PartySidePanel(tab: $tab)
            Button {
                FlowFX.back(app)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 48)
            .padding(.trailing, 6)
            .accessibilityLabel(L("閉じる", "Close"))
            .accessibilityIdentifier("friends_close")
        }
        .onAppear {
            app.friends.start()
            app.friends.refreshPresence()
        }
    }
}

// MARK: - パーティの招待のダイアログ

/// フレンドからパーティに招待された時のダイアログ（ルートに重ねる）: 拒否 / 待って（30 秒後に参加）/ 同意。
struct PartyInviteOverlay: View {
    @Environment(AppModel.self) private var app
    @State private var suppress = false
    @State private var moderation = ModerationPrompt()

    var body: some View {
        // 招待を断って通報の画面を出しても消えないよう、確認と通報の画面は外側（常にある ZStack）に付ける
        ZStack { content }
            .moderationPrompts(moderation)
    }

    @ViewBuilder
    private var content: some View {
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
                    HStack(spacing: 16) {
                        Button {
                            FlowFX.tap(app)
                            let target = Self.target(invite)
                            respond(.decline(suppress: false))
                            moderation.report = target
                        } label: {
                            Label(L("通報する", "Report"), systemImage: "exclamationmark.bubble")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("invite_report")
                        Button {
                            FlowFX.tap(app)
                            moderation.confirm = .block(Self.target(invite))
                        } label: {
                            Label(L("ブロックする", "Block"), systemImage: "hand.raised.fill")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.danger)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("invite_block")
                    }
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

    private static func target(_ invite: PartyInvite) -> PlayerReportTarget {
        PlayerReportTarget(name: invite.name, friendCode: invite.from, source: .invite, roomCode: invite.room,
                           detail: invite.roomName.isEmpty ? nil : L("部屋の名前: \(invite.roomName)", "Room name: \(invite.roomName)"))
    }
}
