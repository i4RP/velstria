import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI008 お知らせ / UI009 メール（一覧 + 詳細の 2 ペイン）。

// MARK: - UI008 お知らせ

struct NoticesView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID: String?

    private var notices: [NoticeDef] {
        LiveOpsService.notices.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }

    var body: some View {
        ScreenScaffold(title: L("お知らせ", "Notices")) {
            let list = notices
            if list.isEmpty {
                VStack(spacing: 0) {
                    FlowEmptyState(symbol: "megaphone", title: L("お知らせはありません", "No notices"),
                                   message: L("新しいお知らせが届くとここに表示されます。", "New announcements will appear here."))
                    patchNotesButton
                        .frame(maxWidth: 280)
                        .padding(.bottom, 16)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 8) {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(list) { n in
                                    Button {
                                        select(n.id)
                                    } label: {
                                        noticeRow(n)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("notice_\(n.id)")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        patchNotesButton
                    }
                    .frame(width: 270)

                    detail(list.first { $0.id == selectedID } ?? list[0])
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .onAppear {
                    if selectedID == nil, let first = list.first { select(first.id, silent: true) }
                }
            }
        }
    }

    private var patchNotesButton: some View {
        Button {
            FlowFX.tap(app)
            app.router.push(.patchNotes)
        } label: {
            Label(L("パッチノート", "Patch Notes"), systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .frame(minHeight: 44)
        .accessibilityIdentifier("notices_patchnotes")
    }

    private func select(_ id: String, silent: Bool = false) {
        if !silent { FlowFX.tap(app) }
        withAnimation(.spring(duration: 0.3)) { selectedID = id }
        if !app.profile.readNoticeIDs.contains(id) {
            app.profile.readNoticeIDs.append(id)
        }
    }

    private func noticeRow(_ n: NoticeDef) -> some View {
        let unread = !app.profile.readNoticeIDs.contains(n.id)
        let selected = selectedID == n.id
        return HStack(spacing: 10) {
            Circle()
                .fill(unread ? Theme.danger : Color.clear)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(L(n.titleJa, n.titleEn))
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(FlowText.date(n.date, time: false))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .glass(cornerRadius: 12, tint: selected ? Theme.gold : Theme.panelStroke, highlighted: selected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((unread ? L("未読 ", "Unread ") : "") + L(n.titleJa, n.titleEn))
    }

    private func detail(_ n: NoticeDef) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(FlowText.date(n.date))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.gold)
                Text(L(n.titleJa, n.titleEn))
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Theme.panelStroke).frame(height: 1)
                Text(L(n.bodyJa, n.bodyEn))
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glass(cornerRadius: 16)
        .id(n.id)
        .transition(.opacity)
    }
}

// MARK: - UI009 メール

struct MailView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID: UUID?
    @State private var now = Date()
    @State private var confirmCleanup = false

    private var mails: [MailItem] {
        app.profile.mail.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScreenScaffold(title: L("メール", "Mail")) {
            let list = mails
            if list.isEmpty {
                FlowEmptyState(symbol: "envelope.open", title: L("メールはありません", "Your mailbox is empty"),
                               message: L("運営からの報酬やお知らせが届くとここに表示されます。", "Rewards and messages will arrive here."))
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 8) {
                        toolbar(list)
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(list) { m in
                                    Button {
                                        open(m.id)
                                    } label: {
                                        mailRow(m)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("mail_row_\(list.firstIndex(of: m) ?? 0)")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(width: 290)

                    if let m = list.first(where: { $0.id == selectedID }) ?? list.first {
                        detail(m)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .onAppear {
                    now = Date()
                    if selectedID == nil, let first = list.first { open(first.id, silent: true) }
                }
            }
        }
        .alert(L("既読メールを削除", "Delete Read Mail"), isPresented: $confirmCleanup) {
            Button(L("削除", "Delete"), role: .destructive) { cleanup() }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("既読で、受け取り済み（または添付なし）のメールを削除します。", "Deletes read mail that has no unclaimed attachments."))
        }
    }

    private func toolbar(_ list: [MailItem]) -> some View {
        let claimable = HomeBadges.claimableMail(app.profile, now: now)
        let removable = list.contains { isRemovable($0) }
        return HStack(spacing: 8) {
            Button(action: claimAll) {
                Label(L("一括受取", "Claim All"), systemImage: "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(claimable == 0)
            .opacity(claimable == 0 ? 0.45 : 1)
            .accessibilityIdentifier("mail_claim_all")

            Button {
                FlowFX.tap(app)
                confirmCleanup = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!removable)
            .opacity(removable ? 1 : 0.4)
            .accessibilityLabel(L("既読メールを削除", "Delete read mail"))
            .accessibilityIdentifier("mail_cleanup")
        }
    }

    private func isRemovable(_ m: MailItem) -> Bool {
        m.read && (m.claimed || m.attachments.isEmpty || HomeBadges.isExpired(m, now: now))
    }

    private func mailRow(_ m: MailItem) -> some View {
        let selected = (selectedID ?? mails.first?.id) == m.id
        let expired = HomeBadges.isExpired(m, now: now)
        return HStack(spacing: 10) {
            Image(systemName: m.read ? "envelope.open.fill" : "envelope.fill")
                .font(.system(size: 18))
                .foregroundStyle(m.read ? Theme.textSecondary : Theme.gold)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title)
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(FlowText.date(m.date, time: false))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                    if !m.attachments.isEmpty {
                        Image(systemName: "paperclip").font(.system(size: 10))
                            .foregroundStyle(m.claimed ? Theme.textSecondary : Theme.cyan)
                    }
                    if expired {
                        Text(L("期限切れ", "Expired")).font(Theme.body(10)).foregroundStyle(Theme.danger)
                    } else if m.claimed {
                        Text(L("受取済み", "Claimed")).font(Theme.body(10)).foregroundStyle(Theme.success)
                    }
                }
            }
            Spacer(minLength: 0)
            if !m.read { Circle().fill(Theme.danger).frame(width: 8, height: 8) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .glass(cornerRadius: 12, tint: selected ? Theme.gold : Theme.panelStroke, highlighted: selected)
        .opacity(expired ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ m: MailItem) -> some View {
        let expired = HomeBadges.isExpired(m, now: now)
        let canClaim = !m.attachments.isEmpty && !m.claimed && !expired
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(FlowText.date(m.date)).font(Theme.mono(11)).foregroundStyle(Theme.gold)
                        Spacer()
                        if let e = m.expiresAt {
                            Label(L("期限 ", "Expires ") + FlowText.date(e), systemImage: "clock")
                                .font(Theme.body(11))
                                .foregroundStyle(expired ? Theme.danger : Theme.textSecondary)
                        }
                    }
                    Text(m.title)
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Theme.panelStroke).frame(height: 1)
                    Text(m.body)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if !m.attachments.isEmpty {
                        FlowSectionTitle(title: L("添付", "Attachments"), symbol: "paperclip")
                            .padding(.top, 6)
                        FlowWrapLayout(spacing: 6) {
                            ForEach(m.attachments.indices, id: \.self) { i in
                                AttachmentChip(attachment: m.attachments[i], claimed: m.claimed)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !m.attachments.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        claim(m.id)
                    } label: {
                        Label(m.claimed ? L("受取済み", "Claimed") : (expired ? L("期限切れ", "Expired") : L("受け取る", "Claim")),
                              systemImage: m.claimed ? "checkmark" : "gift.fill")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canClaim)
                    .opacity(canClaim ? 1 : 0.45)
                    .accessibilityIdentifier("mail_claim")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .glass(cornerRadius: 16)
        .id(m.id)
        .transition(.opacity)
    }

    // MARK: 操作

    private func open(_ id: UUID, silent: Bool = false) {
        if !silent { FlowFX.tap(app) }
        withAnimation(.spring(duration: 0.3)) { selectedID = id }
        if let i = app.profile.mail.firstIndex(where: { $0.id == id }), !app.profile.mail[i].read {
            app.profile.mail[i].read = true
        }
    }

    private func claim(_ id: UUID) {
        var p = app.profile
        let granted = LiveOpsService.claimMail(id: id, profile: &p)
        app.profile = p
        report(granted)
    }

    private func claimAll() {
        var p = app.profile
        let granted = LiveOpsService.claimAllMail(profile: &p)
        app.profile = p
        report(granted)
    }

    private func report(_ granted: [MailAttachment]) {
        if granted.isEmpty {
            FlowFX.error(app)
            app.showToast(L("受け取れるアイテムはありません", "Nothing to claim"))
        } else {
            FlowFX.reward(app)
            app.showToast(L("受け取りました: ", "Received: ") + FlowText.attachmentsSummary(granted, master: app.master))
        }
    }

    private func cleanup() {
        now = Date()
        let removable = app.profile.mail.filter { isRemovable($0) }.map(\.id)
        guard !removable.isEmpty else { return }
        app.profile.mail.removeAll { removable.contains($0.id) }
        if let s = selectedID, removable.contains(s) { selectedID = nil }
        FlowFX.tap(app)
        app.showToast(L("\(removable.count) 件のメールを削除しました", "Deleted \(removable.count) mail"))
    }
}
