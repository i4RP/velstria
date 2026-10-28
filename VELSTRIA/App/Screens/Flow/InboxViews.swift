import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI008 お知らせ / UI009 メール（一覧 + 詳細の 2 ペイン）。

// MARK: - UI008 お知らせ

struct NoticesView: View {
    @Environment(\.isWorldShellEmbedded) private var isEmbedded
    @Environment(AppModel.self) private var app
    @State private var selectedID: String?
    /// 開いた時点で既読だったお知らせ（並べ替えに使う。読んだ物が開いている間に下へ跳ばないように）。
    @State private var readAtOpen: Set<String>?

    /// 未読を上、既読を下（MLBB 2.2.16）。それぞれ新しい順。
    private var notices: [NoticeDef] {
        let read = readAtOpen ?? Set(app.profile.readNoticeIDs)
        return LiveOpsService.notices.sorted { a, b in
            let ra = read.contains(a.id), rb = read.contains(b.id)
            if ra != rb { return !ra }
            return a.date == b.date ? a.id > b.id : a.date > b.date
        }
    }

    var body: some View {
        ScreenScaffold(title: L("お知らせ", "Notices")) {
            let list = notices
            if list.isEmpty {
                VStack(spacing: 0) {
                    EmptyStateView(symbol: "megaphone", title: L("お知らせはありません", "No notices"),
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
                    .frame(width: isEmbedded ? 168 : 270)

                    detail(list.first { $0.id == selectedID } ?? list[0])
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .onAppear {
                    if readAtOpen == nil { readAtOpen = Set(app.profile.readNoticeIDs) }
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

// MARK: - UI009 メール（MLBB 2.2.16 の作り。docs/OUTGAME_GAP.md 10 章・委員会の調べ 2026-10-21）
// 左のタブ: 重要なお知らせ／システム／通報の結果／受信箱／ギフト。未読は明るい青の行と閉じた封筒、既読は暗い色。
// 添付つきは金のギフト箱の印と残り時間（「59d 9h」。保存は約 60 日）。赤い点は未読の重要メールと未読の添付つきだけ。
// 本文はモーダルで開き、「受け取る」で添付を受け取る。右下に「すべて削除」「すべて既読にする」「すべて受け取る（金）」。

/// メールのタブ分け（端末で作ったメールは、添付があればギフト、無ければシステム）。
enum MailBox {
    static func category(_ m: MailItem) -> MailCategory {
        if let c = m.category { return c }
        if m.important == true { return .important }
        return m.attachments.isEmpty ? .system : .gift
    }

    static func title(_ c: MailCategory) -> String {
        switch c {
        case .important: return L("重要なお知らせ", "Important")
        case .system: return L("システム", "System")
        case .report: return L("通報の結果", "Reports")
        case .inbox: return L("受信箱", "Inbox")
        case .gift: return L("ギフト", "Gifts")
        }
    }

    static func symbol(_ c: MailCategory) -> String {
        switch c {
        case .important: return "exclamationmark.circle.fill"
        case .system: return "gearshape.fill"
        case .report: return "flag.fill"
        case .inbox: return "tray.fill"
        case .gift: return "gift.fill"
        }
    }

    /// タブの中の並び（重要な未読を先に、あとは新しい順）。
    static func sorted(_ list: [MailItem]) -> [MailItem] {
        list.sorted { a, b in
            let ia = a.important == true && !a.read, ib = b.important == true && !b.read
            if ia != ib { return ia }
            return a.date > b.date
        }
    }

    /// 添付の残り時間（「59d 9h」。期限が無ければ nil）。
    static func remaining(_ m: MailItem, now: Date) -> String? {
        guard let e = m.expiresAt, !m.attachments.isEmpty else { return nil }
        let s = max(0, Int(e.timeIntervalSince(now)))
        let d = s / 86_400, h = (s % 86_400) / 3600, mm = (s % 3600) / 60
        return d > 0 ? "\(d)d \(h)h" : (h > 0 ? "\(h)h \(mm)m" : "\(mm)m")
    }

    /// すべて削除で消せるか（既読で、受け取れる添付が残っていない）。
    static func isRemovable(_ m: MailItem, now: Date) -> Bool {
        m.read && (m.claimed || m.attachments.isEmpty || HomeBadges.isExpired(m, now: now))
    }
}

struct MailView: View {
    @Environment(\.isWorldShellEmbedded) private var isEmbedded
    @Environment(AppModel.self) private var app
    @State private var tab: MailCategory = .important
    @State private var openedID: UUID?
    @State private var now = Date()
    @State private var confirmDeleteAll = false
    @State private var confirmDeleteOne: UUID?
    @State private var chosenTab = false

    private func list(_ c: MailCategory) -> [MailItem] {
        MailBox.sorted(app.profile.mail.filter { MailBox.category($0) == c })
    }

    var body: some View {
        ScreenScaffold(title: L("メール", "Mail")) {
            HStack(alignment: .top, spacing: 12) {
                tabs.frame(width: isEmbedded ? 112 : 150)
                VStack(spacing: 8) {
                    let items = list(tab)
                    if items.isEmpty {
                        EmptyStateView(symbol: "envelope.open", title: L("メールはありません", "No mail here"),
                                       message: L("運営からの報酬やお知らせが届くとここに表示されます。", "Rewards and messages will arrive here."))
                            .glass(cornerRadius: 14)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(items) { m in
                                    Button { open(m.id) } label: { mailRow(m) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("mail_row_\(items.firstIndex(of: m) ?? 0)")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    bottomButtons(items)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .overlay {
            if let id = openedID, let m = app.profile.mail.first(where: { $0.id == id }) {
                modal(m)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: openedID)
        .onAppear {
            now = Date()
            // 最初は点のあるタブ（無ければ重要なお知らせ）を開く
            if !chosenTab, let c = MailCategory.allCases.first(where: { c in list(c).contains { HomeBadges.mailNeedsDot($0, now: now) } }) {
                tab = c
            }
            chosenTab = true
        }
        .alert(L("メールを削除", "Delete Mail"), isPresented: $confirmDeleteAll) {
            Button(L("削除", "Delete"), role: .destructive) { deleteAll() }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("このタブの既読で、受け取り済み（または添付なし）のメールを削除します。", "Deletes read mail in this tab that has nothing left to claim."))
        }
        .alert(L("受け取っていない添付があります", "Unclaimed attachments"), isPresented: Binding(get: { confirmDeleteOne != nil }, set: { if !$0 { confirmDeleteOne = nil } })) {
            Button(L("削除", "Delete"), role: .destructive) {
                if let id = confirmDeleteOne { delete(id) }
            }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("削除すると添付は受け取れなくなります。", "If you delete it, you can't claim the attachments."))
        }
    }

    // MARK: 左のタブ

    private var tabs: some View {
        VStack(spacing: 6) {
            ForEach(MailCategory.allCases, id: \.self) { c in
                let selected = tab == c
                let dot = list(c).contains { HomeBadges.mailNeedsDot($0, now: now) }
                Button {
                    guard tab != c else { return }
                    app.audio.play(.uiTab)
                    withAnimation(.easeInOut(duration: 0.2)) { tab = c }
                } label: {
                    Label(MailBox.title(c), systemImage: MailBox.symbol(c))
                        .font(Celestial.heading(12))
                        .foregroundStyle(selected ? Color(red: 0.16, green: 0.10, blue: 0.03) : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(HomeChamfer(cut: 7).fill(selected ? AnyShapeStyle(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                                                                      : AnyShapeStyle(Celestial.ink.opacity(0.8))))
                        .overlay(HomeChamfer(cut: 7).stroke(selected ? HomeStyle.goldLight : Celestial.ice.opacity(0.4), lineWidth: selected ? 1 : 0.6))
                        .overlay(alignment: .topTrailing) {
                            if dot { Circle().fill(Color.red).frame(width: 8, height: 8).overlay(Circle().stroke(.white, lineWidth: 0.6)).offset(x: -4, y: 4) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mail_tab_\(c.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 一覧

    private func mailRow(_ m: MailItem) -> some View {
        let expired = HomeBadges.isExpired(m, now: now)
        let unread = !m.read
        return HStack(spacing: 10) {
            Image(systemName: unread ? "envelope.fill" : "envelope.open.fill")
                .font(.system(size: 18))
                .foregroundStyle(unread ? Color(red: 0.75, green: 0.92, blue: 1) : Theme.textSecondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if m.important == true {
                        Text(L("重要", "Important"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.danger))
                    }
                    Text(m.title)
                        .font(Theme.heading(13))
                        .foregroundStyle(unread ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(FlowText.date(m.date, time: false))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                    if expired {
                        Text(L("期限切れ", "Expired")).font(Theme.body(10)).foregroundStyle(Theme.danger)
                    } else if m.claimed {
                        Text(L("受取済み", "Claimed")).font(Theme.body(10)).foregroundStyle(Theme.success)
                    } else if let left = MailBox.remaining(m, now: now) {
                        Label(left, systemImage: "clock").font(Theme.mono(10)).foregroundStyle(HomeStyle.goldLight)
                    }
                }
            }
            Spacer(minLength: 0)
            if !m.attachments.isEmpty {
                // 添付つき: 金のギフト箱（受け取った後は薄く）
                Image(systemName: "gift.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(m.claimed || expired ? Theme.textSecondary.opacity(0.5) : Theme.gold)
            }
            if HomeBadges.mailNeedsDot(m, now: now) { Circle().fill(Color.red).frame(width: 8, height: 8) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        // 未読は明るい青、既読は暗い色（MLBB と同じ）
        .background(HomeChamfer(cut: 8).fill(unread ? Color(red: 0.16, green: 0.38, blue: 0.68).opacity(0.75) : Celestial.ink.opacity(0.75)))
        .overlay(HomeChamfer(cut: 8).stroke(unread ? Color(red: 0.55, green: 0.82, blue: 1).opacity(0.7) : Celestial.ice.opacity(0.2), lineWidth: 0.7))
        .opacity(expired ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    /// 右下: すべて削除・すべて既読にする・すべて受け取る（金）。このタブの中だけ。
    private func bottomButtons(_ items: [MailItem]) -> some View {
        let removable = items.contains { MailBox.isRemovable($0, now: now) }
        let unread = items.contains { !$0.read }
        let claimable = items.contains { !$0.claimed && !$0.attachments.isEmpty && !HomeBadges.isExpired($0, now: now) }
        return HStack(spacing: 8) {
            Spacer(minLength: 0)
            smallButton(L("すべて削除", "Delete All"), "trash", id: "mail_cleanup", enabled: removable) {
                FlowFX.tap(app)
                confirmDeleteAll = true
            }
            smallButton(L("すべて既読にする", "Read All"), "envelope.open", id: "mail_read_all", enabled: unread) { readAll(items) }
            Button { claimAll(items) } label: {
                Label(L("すべて受け取る", "Claim All"), systemImage: "gift.fill")
                    .font(Celestial.heading(12))
                    .foregroundStyle(Color(red: 0.25, green: 0.15, blue: 0.02))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(HomeChamfer(cut: 7).fill(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!claimable)
            .opacity(claimable ? 1 : 0.45)
            .accessibilityIdentifier("mail_claim_all")
        }
    }

    private func smallButton(_ title: String, _ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Celestial.heading(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .background(HomeChamfer(cut: 7).fill(Celestial.ink.opacity(0.85)))
                .overlay(HomeChamfer(cut: 7).stroke(Celestial.ice.opacity(0.45), lineWidth: 0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(id)
    }

    // MARK: 本文（モーダル）

    private func modal(_ m: MailItem) -> some View {
        let expired = HomeBadges.isExpired(m, now: now)
        let canClaim = !m.attachments.isEmpty && !m.claimed && !expired
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { openedID = nil }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(FlowText.date(m.date)).font(Theme.mono(11)).foregroundStyle(Theme.gold)
                    Spacer()
                    if let left = MailBox.remaining(m, now: now), !m.claimed, !expired {
                        Label(L("残り ", "Expires in ") + left, systemImage: "clock")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Button { openedID = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("閉じる", "Close"))
                    .accessibilityIdentifier("mail_close")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(m.title)
                            .font(Theme.title(19))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Rectangle().fill(Theme.panelStroke).frame(height: 1)
                        Text(m.body)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textPrimary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if !m.attachments.isEmpty {
                            SectionTitle(title: L("添付", "Attachments"), symbol: "gift.fill").padding(.top, 6)
                            FlowWrapLayout(spacing: 6) {
                                ForEach(m.attachments.indices, id: \.self) { i in
                                    RewardChip(attachment: m.attachments[i], claimed: m.claimed)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    smallButton(L("削除", "Delete"), "trash", id: "mail_delete", enabled: true) { requestDelete(m) }
                    Spacer()
                    if !m.attachments.isEmpty {
                        Button { claim(m.id) } label: {
                            Label(m.claimed ? L("受取済み", "Claimed") : (expired ? L("期限切れ", "Expired") : L("受け取る", "Claim")),
                                  systemImage: m.claimed ? "checkmark" : "gift.fill")
                                .frame(minWidth: 150)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canClaim)
                        .opacity(canClaim ? 1 : 0.45)
                        .accessibilityIdentifier("mail_claim")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: 560, maxHeight: 320)
            .background(HomeChamfer(cut: 14).fill(Celestial.inkRaised))
            .overlay(HomeChamfer(cut: 14).stroke(Celestial.ice.opacity(0.5), lineWidth: 0.8))
            .padding(20)
        }
    }

    // MARK: 操作

    private func open(_ id: UUID) {
        FlowFX.tap(app)
        withAnimation { openedID = id }
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

    /// このタブの受け取れる添付をすべて受け取る（既読にもなる）。
    private func claimAll(_ items: [MailItem]) {
        var p = app.profile
        var granted: [MailAttachment] = []
        for m in items where !m.claimed && !m.attachments.isEmpty {
            granted += LiveOpsService.claimMail(id: m.id, profile: &p)
            if let i = p.mail.firstIndex(where: { $0.id == m.id }) { p.mail[i].read = true }
        }
        app.profile = p
        report(granted)
    }

    private func readAll(_ items: [MailItem]) {
        FlowFX.tap(app)
        let ids = Set(items.map(\.id))
        var p = app.profile
        for i in p.mail.indices where ids.contains(p.mail[i].id) { p.mail[i].read = true }
        app.profile = p
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

    /// 1 通を消す（受け取っていない添付があれば確かめる）。
    private func requestDelete(_ m: MailItem) {
        FlowFX.tap(app)
        if !m.attachments.isEmpty && !m.claimed && !HomeBadges.isExpired(m, now: now) {
            confirmDeleteOne = m.id
        } else {
            delete(m.id)
        }
    }

    private func delete(_ id: UUID) {
        app.profile.mail.removeAll { $0.id == id }
        if openedID == id { openedID = nil }
        confirmDeleteOne = nil
        app.showToast(L("メールを削除しました", "Mail deleted"))
    }

    /// このタブの既読で受け取る物の無いメールを消す。
    private func deleteAll() {
        now = Date()
        let removable = list(tab).filter { MailBox.isRemovable($0, now: now) }.map(\.id)
        guard !removable.isEmpty else { return }
        app.profile.mail.removeAll { removable.contains($0.id) }
        if let o = openedID, removable.contains(o) { openedID = nil }
        FlowFX.tap(app)
        app.showToast(L("\(removable.count) 件のメールを削除しました", "Deleted \(removable.count) mail"))
    }
}
