import SwiftUI
import VelstriaCore

// 担当: online。オンライン対戦のパーティ（メンバー集め）の画面。部屋の段階が party の間はこれを出す（OnlineLobbyView が切り替える）。
// - 左: 題名・AI の強さ（ホスト）・部屋コード / メンバーの枠（5 つ。6 人以上なら 10）/ ゲーム開始
// - 右のパネル: フレンド（在席・招待）/ フレンド申請（自分のコード・コードで申請・届いた申請）/ 近く（同じ Wi-Fi）/ 部屋コードで参加
// - 「ゲーム開始」（ホスト）→ チーム分け（全員味方 / 敵味方に分かれる）→ ピックの段階（OnlineRoomView の座席）へ
// フレンド申請は部屋と関係なく受信箱（FriendHub）で送り合う。パーティの枠からも、フレンドでない参加者へ申請できる。

/// パーティの右パネルのタブ。
enum PartySideTab: String, CaseIterable, Identifiable {
    case friends, requests, nearby, code

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .friends: return "person.2.fill"
        case .requests: return "person.badge.plus"
        case .nearby: return "wifi"
        case .code: return "number"
        }
    }

    var title: String {
        switch self {
        case .friends: return L("フレンド", "Friends")
        case .requests: return L("フレンド申請", "Friend Requests")
        case .nearby: return L("近くの部屋（同じ Wi-Fi）", "Nearby (Same Wi-Fi)")
        case .code: return L("部屋コードで参加", "Join by Room Code")
        }
    }
}

/// パーティの枠に出すメンバー。
struct PartyMember: Identifiable, Equatable {
    var id: String
    var name: String
    var avatar: String?
    var friendCode: String?
    var isHost: Bool
    var isMe: Bool
    var rtt: Double?
}

struct PartyLobbyView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: PartySideTab = .friends
    @State private var showsTeamSetup = false
    @State private var confirmsLeave = false

    private var session: OnlineSession? { app.online }
    private var isHost: Bool { session?.isHost ?? true }
    private var isConnecting: Bool { session?.status == .connecting }

    var body: some View {
        GeometryReader { geo in
            let sideWidth = min(340, max(250, geo.size.width * 0.34))
            HStack(spacing: 0) {
                mainArea
                    .padding(.leading, 12)
                    .padding(.trailing, 14)
                PartySidePanel(tab: $tab)
                    .frame(width: sideWidth)
            }
        }
        .background(PartyBackdrop())
        .overlay {
            if showsTeamSetup, let session {
                TeamSetupOverlay(session: session, onClose: { showsTeamSetup = false })
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            app.ensurePartyRoom()
            app.friends.start()
            app.friends.refreshPresence()
            // -partyTeams: チーム分けを開いた状態で始める（画面の確認用）
            if DebugLaunch.isEnabled, DebugLaunch.args.contains("-partyTeams") { showsTeamSetup = true }
        }
        .confirmationDialog(isHost ? L("パーティを解散しますか？", "Disband the party?") : L("パーティから抜けますか？", "Leave the party?"),
                            isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button(isHost ? L("解散する", "Disband") : L("抜ける", "Leave"), role: .destructive) { leaveAndClose() }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: 左側

    private var mainArea: some View {
        VStack(spacing: 10) {
            header
            slots
                .frame(maxHeight: .infinity)
            bottomBar
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                FlowFX.back(app)
                if (session?.connectedPeerCount ?? 1) > 1 || session?.isHost == false {
                    confirmsLeave = true
                } else {
                    leaveAndClose()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("戻る", "Back"))
            .accessibilityIdentifier("nav_back")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L("オンライン対戦", "Online Match"))
                        .font(Theme.title(21))
                        .foregroundStyle(Theme.gold)
                    Text(L("- パーティ", "- Party"))
                        .font(Theme.title(16))
                        .foregroundStyle(Theme.success)
                }
                .lineLimit(1)
                .fixedSize()
                difficultyMenu
            }
            Spacer(minLength: 8)
            roomBadge
        }
    }

    /// AI の強さ（ホストは選べる。参加者には表示だけ）。
    @ViewBuilder
    private var difficultyMenu: some View {
        let current = session?.room.botDifficulty ?? .normal
        let label = HStack(spacing: 6) {
            Image(systemName: "cpu")
            Text(L("AI: \(FlowText.difficulty(current))", "AI: \(FlowText.difficulty(current))"))
            if isHost { Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy)) }
        }
        .font(Theme.body(13))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.cyan.opacity(0.7), lineWidth: 1))
        if isHost, let session {
            Menu {
                ForEach(Difficulty.allCases, id: \.self) { d in
                    Button {
                        FlowFX.tap(app)
                        session.setBotDifficulty(d)
                    } label: {
                        if d == current {
                            Label(FlowText.difficulty(d), systemImage: "checkmark")
                        } else {
                            Text(FlowText.difficulty(d))
                        }
                    }
                }
            } label: { label }
            .accessibilityIdentifier("party_difficulty")
        } else {
            label
        }
    }

    /// 右上: ホストは部屋コード（コピー・共有）、参加者は部屋の名前と遅延。
    @ViewBuilder
    private var roomBadge: some View {
        if let session {
            if session.isHost {
                if session.relayCode != nil {
                    RelayInviteControls(session: session)
                } else {
                    Text(L("部屋コードを準備中…", "Preparing room code…"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.room.name.isEmpty ? L("接続中…", "Connecting…") : session.room.name)
                        .font(Theme.heading(13))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let rtt = session.rtt {
                        Text(String(format: "%.0f ms", rtt * 1000))
                            .font(Theme.mono(11))
                            .foregroundStyle(PartySlotCard.pingColor(rtt))
                    }
                }
            }
        }
    }

    // MARK: メンバーの枠

    private var members: [PartyMember] {
        guard let session, !session.room.hostPeerID.isEmpty else {
            let name = app.profile.displayName.isEmpty ? L("プレイヤー", "Player") : app.profile.displayName
            return [PartyMember(id: app.profile.playerID, name: name, avatar: app.profile.avatarHeroID,
                                friendCode: app.profile.friendCode, isHost: true, isMe: true, rtt: nil)]
        }
        let room = session.room
        let players = room.players
        let ordered = players.filter { $0.id == room.hostPeerID } + players.filter { $0.id != room.hostPeerID }
        return ordered.map { p in
            let me = p.id == app.profile.playerID
            return PartyMember(id: p.id, name: p.name, avatar: me ? app.profile.avatarHeroID : p.avatar,
                               friendCode: p.friendCode, isHost: p.id == room.hostPeerID, isMe: me,
                               rtt: me && !session.isHost ? session.rtt : p.rtt)
        }
    }

    private var slots: some View {
        let list = members
        let count = list.count > 5 ? 10 : 5
        return ZStack {
            if count == 5 {
                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { i in slot(i < list.count ? list[i] : nil, compact: false) }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { col in
                                let i = row * 5 + col
                                slot(i < list.count ? list[i] : nil, compact: true)
                            }
                        }
                    }
                }
            }
            if isConnecting {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.cyan)
                    Text(L("パーティに接続しています…", "Joining the party…"))
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(14)
                .background(Capsule().fill(Color.black.opacity(0.6)))
            }
        }
    }

    private func slot(_ member: PartyMember?, compact: Bool) -> some View {
        PartySlotCard(member: member, compact: compact,
                      friendState: member.map(friendState(of:)) ?? .none,
                      onInvite: {
                          FlowFX.tap(app)
                          tab = .friends
                      },
                      onAddFriend: { code in
                          FlowFX.confirm(app)
                          _ = app.friends.requestFriend(code: code)
                      })
    }

    private func friendState(of member: PartyMember) -> PartySlotCard.FriendState {
        guard !member.isMe, let code = member.friendCode else { return .none }
        if app.friends.friend(code: code) != nil { return .friend }
        if app.friends.hasOutgoingRequest(to: code) { return .requested }
        return .canRequest(code)
    }

    // MARK: 下の帯

    private var bottomBar: some View {
        ZStack {
            HStack(spacing: 10) {
                if let session, session.connectedPeerCount > 1 || !session.isHost {
                    Button {
                        FlowFX.back(app)
                        confirmsLeave = true
                    } label: {
                        Label(session.isHost ? L("解散", "Disband") : L("抜ける", "Leave"), systemImage: "rectangle.portrait.and.arrow.right")
                            .font(Theme.body(12))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("party_leave")
                }
                if let n = session?.room.spectators.count, n > 0 {
                    Label(L("観戦 \(n)", "\(n) watching"), systemImage: "eye.fill")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(L("\(members.count) 人", "\(members.count) players"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            startButton
        }
        .frame(minHeight: 56)
    }

    private var startButton: some View {
        let enabled = isHost && !isConnecting
        return Button {
            FlowFX.confirm(app)
            if session == nil { app.ensurePartyRoom() }
            withAnimation(.easeOut(duration: 0.15)) { showsTeamSetup = true }
        } label: {
            Text(isHost ? L("ゲーム開始", "Start Game") : L("ホストの開始を待っています", "Waiting for the host"))
                .font(.system(size: isHost ? 22 : 15, weight: .heavy, design: .serif))
                .foregroundStyle(enabled ? Color(red: 0.28, green: 0.17, blue: 0.04) : Theme.textSecondary)
                .frame(width: 250, height: 54)
                .background(
                    PartyBannerShape().fill(LinearGradient(
                        colors: enabled ? [Color(red: 1.0, green: 0.93, blue: 0.62), Theme.gold, Color(red: 0.86, green: 0.62, blue: 0.22)]
                            : [Color.white.opacity(0.18), Color.white.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom))
                )
                .overlay(PartyBannerShape().stroke(Color.white.opacity(enabled ? 0.85 : 0.3), lineWidth: 2))
                .shadow(color: enabled ? Theme.gold.opacity(0.5) : .clear, radius: 10)
                .contentShape(PartyBannerShape())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("party_start")
    }

    private func leaveAndClose() {
        app.leaveOnlineRoom()
        app.router.pop()
    }
}

// MARK: - 枠

struct PartySlotCard: View {
    enum FriendState: Equatable {
        case none, friend, requested
        case canRequest(String)
    }

    let member: PartyMember?
    var compact = false
    var friendState: FriendState = .none
    var onInvite: () -> Void
    var onAddFriend: (String) -> Void

    static func pingColor(_ rtt: Double) -> Color {
        rtt < 0.09 ? Theme.success : (rtt < 0.18 ? Theme.gold : Theme.danger)
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.32, blue: 0.62).opacity(0.85),
                                              Color(red: 0.16, green: 0.46, blue: 0.80).opacity(0.35)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(member?.isMe == true ? Theme.gold.opacity(0.8) : Color.white.opacity(0.18), lineWidth: 1))
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.cyan.opacity(0.7)).frame(height: 2)
                }
            Image(systemName: "suit.diamond.fill")
                .font(.system(size: compact ? 10 : 14))
                .foregroundStyle(Theme.cyan)
                .offset(y: compact ? -5 : -7)
            if let member {
                filled(member)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var portraitSize: CGFloat { compact ? 40 : 66 }

    private func filled(_ m: PartyMember) -> some View {
        VStack(spacing: compact ? 3 : 6) {
            HStack(spacing: 3) {
                if let rtt = m.rtt {
                    Text("\(Int((rtt * 1000).rounded()))ms")
                        .font(.system(size: compact ? 9 : 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.pingColor(rtt))
                }
                if m.isHost {
                    Image(systemName: "house.fill")
                        .font(.system(size: compact ? 9 : 12))
                        .foregroundStyle(Theme.gold)
                        .accessibilityLabel(L("ホスト", "Host"))
                }
            }
            .frame(minHeight: compact ? 12 : 16)
            HeroPortraitView(heroID: m.avatar ?? "H001", size: portraitSize, showsRole: false)
                .overlay(RoundedRectangle(cornerRadius: portraitSize * 0.2, style: .continuous)
                    .stroke(m.isMe ? Theme.gold : Color.white.opacity(0.5), lineWidth: 2))
            Text(m.name)
                .font(Theme.heading(compact ? 11 : 15))
                .foregroundStyle(m.isMe ? Theme.gold : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
            tag(m)
            Spacer(minLength: 0)
        }
        .padding(.top, compact ? 10 : 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("party_slot_\(m.id)")
    }

    @ViewBuilder
    private func tag(_ m: PartyMember) -> some View {
        if m.isMe {
            badge(L("あなた", "You"), color: Theme.gold)
        } else {
            switch friendState {
            case .friend:
                badge(L("フレンド", "Friend"), color: Theme.success)
            case .requested:
                badge(L("申請中", "Requested"), color: Theme.textSecondary)
            case .canRequest(let code):
                Button {
                    onAddFriend(code)
                } label: {
                    Label(L("申請", "Add"), systemImage: "person.badge.plus")
                        .font(.system(size: compact ? 9 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .frame(minHeight: compact ? 22 : 28)
                        .background(Capsule().fill(Theme.cyan))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("\(m.name) にフレンド申請", "Send a friend request to \(m.name)"))
                .accessibilityIdentifier("party_add_friend_\(m.id)")
            case .none:
                EmptyView()
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    private var empty: some View {
        Button(action: onInvite) {
            VStack(spacing: compact ? 4 : 8) {
                Text("?")
                    .font(.system(size: compact ? 26 : 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: portraitSize, height: portraitSize)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.05, green: 0.16, blue: 0.32).opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.cyan.opacity(0.35), lineWidth: 1))
                Text(L("招待", "Invite"))
                    .font(Theme.body(compact ? 9 : 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, compact ? 22 : 42)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("空き枠: フレンドを招待", "Empty slot: invite a friend"))
    }
}

/// 「ゲーム開始」の帯（両端が尖った横長の六角形）。
struct PartyBannerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tip = min(rect.height * 0.5, rect.width * 0.2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + tip, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + tip, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// パーティの背景: 明るめの青空のグラデーション + ホームの背景アートを薄く重ねる。
struct PartyBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.20, blue: 0.48),
                                    Color(red: 0.12, green: 0.42, blue: 0.78),
                                    Color(red: 0.36, green: 0.66, blue: 0.92)],
                           startPoint: .top, endPoint: .bottom)
            if let art = UIImage(named: "HomeBackdrop") {
                Color.clear
                    .overlay {
                        Image(uiImage: art)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .opacity(0.28)
                    .blendMode(.screen)
            }
            RadialGradient(colors: [Color.white.opacity(0.22), .clear], center: UnitPoint(x: 0.3, y: 0.2),
                           startRadius: 0, endRadius: 420)
            LinearGradient(colors: [.clear, Color(red: 0.03, green: 0.08, blue: 0.22).opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 右のパネル

struct PartySidePanel: View {
    @Binding var tab: PartySideTab
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            HStack(spacing: 6) {
                Spacer()
                Text(tab.title)
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.textPrimary)
                statusDot
                Spacer()
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.cyan.opacity(0.8))
                    .offset(y: 6)
            }
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 10)
        .background(
            LinearGradient(colors: [Color(red: 0.12, green: 0.28, blue: 0.62).opacity(0.94),
                                    Color(red: 0.08, green: 0.16, blue: 0.40).opacity(0.97)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.cyan.opacity(0.4)).frame(width: 1) }
                .ignoresSafeArea()
        )
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PartySideTab.allCases) { t in
                Button {
                    FlowFX.tap(app)
                    tab = t
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(tab == t ? Color.white : Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity, minHeight: 44)
                        if t == .requests, app.friends.incomingRequests.count > 0 {
                            Text("\(app.friends.incomingRequests.count)")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.danger))
                                .offset(x: -10, y: 4)
                        }
                    }
                    .background(tab == t ? Color.white.opacity(0.12) : .clear)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(tab == t ? Theme.cyan : .clear).frame(height: 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
                .accessibilityIdentifier("party_tab_\(t.rawValue)")
            }
        }
        .padding(.top, 4)
    }

    /// フレンドの受信箱の状態（緑 = オンライン）。
    private var statusDot: some View {
        let color: Color
        switch app.friends.status {
        case .online: color = Theme.success
        case .failed: color = Theme.danger
        case .connecting, .offline: color = Theme.textSecondary
        }
        return Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .friends:
            PartyFriendsTab(onAddFriend: { tab = .requests })
        case .requests:
            PartyRequestsTab()
        case .nearby:
            ScrollView {
                OnlineLANSection().padding(.vertical, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
        case .code:
            ScrollView {
                OnlineCodeJoinSection().padding(.vertical, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: フレンド（招待）

struct PartyFriendsTab: View {
    var onAddFriend: () -> Void
    @Environment(AppModel.self) private var app
    @State private var removing: Friend?

    private var hub: FriendHub { app.friends }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                connectionNotice
                if hub.friends.isEmpty {
                    emptyState
                } else {
                    let online = hub.friends.filter { hub.isFriendOnline($0.code) }
                    let offline = hub.friends.filter { !hub.isFriendOnline($0.code) }
                    sectionHeader(L("オンライン（\(online.count)）", "Online (\(online.count))"))
                    ForEach(online) { row($0, online: true) }
                    sectionHeader(L("オフライン（\(offline.count)）", "Offline (\(offline.count))"))
                    ForEach(offline) { row($0, online: false) }
                    Button {
                        FlowFX.tap(app)
                        onAddFriend()
                    } label: {
                        Label(L("フレンドを追加", "Add a friend"), systemImage: "person.badge.plus")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.cyan)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { hub.refreshPresence() }
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

    @ViewBuilder
    private var connectionNotice: some View {
        switch hub.status {
        case .online:
            EmptyView()
        case .connecting, .offline:
            HStack(spacing: 6) {
                ProgressView().tint(Theme.cyan).scaleEffect(0.8)
                Text(L("フレンドサーバーに接続中…", "Connecting to the friend server…"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        case .failed(let reason):
            Text(reason)
                .font(Theme.body(11))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textSecondary)
            Text(L("まだフレンドがいません。\nフレンドコードを交換して申請しましょう（部屋を作らなくても申請できます）。",
                   "No friends yet.\nExchange friend codes to send a request (no room needed)."))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                FlowFX.confirm(app)
                onAddFriend()
            } label: {
                Label(L("フレンドを追加", "Add a friend"), systemImage: "person.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
            .accessibilityIdentifier("party_add_friend")
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
    }

    private func sectionHeader(_ text: String) -> some View {
        VStack(spacing: 2) {
            Text(text)
                .font(Theme.heading(13))
                .foregroundStyle(Theme.textPrimary)
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.cyan.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func inParty(_ code: String) -> Bool {
        app.online?.room.peers.contains { $0.friendCode == code } == true
    }

    private func row(_ friend: Friend, online: Bool) -> some View {
        let status = statusLine(friend, online: online)
        return HStack(spacing: 10) {
            FriendAvatar(name: friend.name, code: friend.code, online: online)
            VStack(alignment: .leading, spacing: 2) {
                Text(FriendNames.display(friend.name))
                    .font(Theme.heading(14))
                    .foregroundStyle(online ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Text(FriendCode.display(friend.code))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                Label(status.text, systemImage: status.symbol)
                    .font(Theme.body(11))
                    .foregroundStyle(status.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            action(friend, online: online)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                removing = friend
            } label: {
                Label(L("フレンドから外す", "Remove friend"), systemImage: "person.crop.circle.badge.minus")
            }
        }
        .accessibilityIdentifier("party_friend_\(friend.code)")
    }

    private func statusLine(_ friend: Friend, online: Bool) -> (text: String, symbol: String, color: Color) {
        if inParty(friend.code) { return (L("パーティにいます", "In your party"), "checkmark.seal.fill", Theme.gold) }
        if let sent = hub.sentInvite(to: friend.code) {
            switch sent.state {
            case .pending: return (L("招待済み", "Invited"), "checkmark.square.fill", Theme.success)
            case .accepted: return (L("参加します", "Joining"), "arrow.right.circle.fill", Theme.success)
            case .waiting: return (L("少し待ってから参加", "Joining shortly"), "hourglass", Theme.gold)
            case .declined: return (L("招待を断りました", "Declined"), "xmark.square.fill", Theme.danger)
            case .busy: return (L("試合中", "In a match"), "gamecontroller.fill", Theme.gold)
            }
        }
        return online ? (L("オンライン", "Online"), "circle.fill", Theme.success)
                      : (L("オフライン", "Offline"), "xmark.square", Theme.textSecondary)
    }

    @ViewBuilder
    private func action(_ friend: Friend, online: Bool) -> some View {
        if inParty(friend.code) {
            EmptyView()
        } else if let sent = hub.sentInvite(to: friend.code), sent.state == .pending || sent.state == .waiting {
            actionSquare(symbol: "hourglass", fill: Color(red: 0.62, green: 0.32, blue: 0.85))
                .accessibilityLabel(L("返事を待っています", "Waiting for a reply"))
        } else if online {
            Button {
                FlowFX.confirm(app)
                app.inviteToParty(friend)
            } label: {
                actionSquare(symbol: "plus", fill: Color(red: 0.16, green: 0.62, blue: 0.52))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(FriendNames.display(friend.name)) をパーティに招待", "Invite \(FriendNames.display(friend.name)) to the party"))
            .accessibilityIdentifier("party_invite_\(friend.code)")
        } else {
            actionSquare(symbol: "envelope", fill: Color.white.opacity(0.12))
                .opacity(0.6)
                .accessibilityLabel(L("オフラインのため招待できません", "Offline"))
        }
    }

    private func actionSquare(symbol: String, fill: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 48, height: 36)
            .background(RoundedRectangle(cornerRadius: 3).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.35), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// フレンドのアイコン（頭文字 + コードから決めた色。在席なら緑の点）。
struct FriendAvatar: View {
    let name: String
    let code: String
    var online = true
    var size: CGFloat = 44

    var body: some View {
        let hue = Double(code.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 997 }) / 997
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.6, brightness: 0.9),
                                              Color(hue: hue, saturation: 0.8, brightness: 0.35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(FriendNames.display(name).prefix(1)))
                        .font(.system(size: size * 0.45, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                )
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.5), lineWidth: 1))
                .saturation(online ? 1 : 0.2)
            if online {
                Circle().fill(Theme.success).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .offset(x: -3, y: -3)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: フレンド申請

struct PartyRequestsTab: View {
    @Environment(AppModel.self) private var app
    @State private var codeInput = ""

    private var hub: FriendHub { app.friends }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                myCode
                addField
                if !hub.incomingRequests.isEmpty { incoming }
                outgoing
                Text(L("部屋を作らなくても、フレンドコードを伝え合うだけで申請できます。相手がオフラインでも申請は預かられ、次に開いた時に届きます。",
                       "No room needed: just exchange friend codes. Requests to offline players are kept and delivered when they open the app."))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var myCode: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("あなたのフレンドコード", "Your friend code"))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 2) {
                Text(FriendCode.display(hub.myCode))
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("party_my_code")
                Spacer(minLength: 0)
                Button {
                    FlowFX.tap(app)
                    UIPasteboard.general.string = hub.myCode
                    app.showToast(L("フレンドコードをコピーしました", "Friend code copied"))
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("フレンドコードをコピー", "Copy friend code"))
                ShareLink(item: FriendLink.shareText(code: hub.myCode, name: hub.myName)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("フレンドコードを共有", "Share friend code"))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
    }

    private var parsedCode: Result<String, FriendCode.InputError> { FriendCode.parse(codeInput) }
    private var codeIsValid: Bool { if case .success = parsedCode { return true } else { return false } }
    private var codeHasError: Bool {
        switch parsedCode {
        case .failure(.ambiguous), .failure(.invalid), .failure(.tooLong): return true
        default: return false
        }
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("相手のフレンドコードで申請", "Send a request by friend code"))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                TextField("", text: $codeInput, prompt: Text("ABCD EFGH").foregroundStyle(Theme.textSecondary.opacity(0.5)))
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .onChange(of: codeInput) { _, v in
                        let cleaned = FriendCode.cleaned(v)
                        if cleaned != v { codeInput = cleaned }
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(codeHasError ? Theme.danger : Theme.panelStroke, lineWidth: 1))
                    .accessibilityLabel(L("相手のフレンドコード", "Friend code"))
                    .accessibilityIdentifier("party_friend_code_field")
                Button {
                    send()
                } label: {
                    Text(L("申請", "Send"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .opacity(codeIsValid ? 1 : 0.5)
                .accessibilityIdentifier("party_friend_send")
            }
            if codeHasError, case .failure(let e) = parsedCode {
                Text(e.message)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func send() {
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

    private var incoming: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L("届いた申請（\(hub.incomingRequests.count)）", "Requests (\(hub.incomingRequests.count))"), systemImage: "bell.badge.fill")
                .font(Theme.heading(13))
                .foregroundStyle(Theme.gold)
            ForEach(hub.incomingRequests) { request in
                HStack(spacing: 8) {
                    FriendAvatar(name: request.name, code: request.code, online: true, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(FriendNames.display(request.name)).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text(FriendCode.display(request.code)).font(Theme.mono(9)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 2)
                    Button {
                        FlowFX.tap(app)
                        hub.ignore(request)
                    } label: {
                        Text(L("無視", "Ignore")).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 40, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("party_ignore_\(request.code)")
                    Button {
                        FlowFX.confirm(app)
                        hub.approve(request)
                    } label: {
                        Text(L("承認", "Accept"))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Capsule().fill(Theme.gold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("party_approve_\(request.code)")
                }
            }
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        let codes = app.profile.outgoingFriendRequests.filter { hub.friend(code: $0) == nil }
        if !codes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(L("承認待ち（\(codes.count)）", "Pending (\(codes.count))"), systemImage: "paperplane.fill")
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(codes, id: \.self) { code in
                    HStack {
                        Text(FriendCode.display(code)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(L("返事を待っています", "Waiting")).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(minHeight: 28)
                }
            }
        }
    }
}

// MARK: - チーム分け

/// 「ゲーム開始」の後: 全員味方（相手は AI）か、敵味方に分かれるかを決めてピックへ進む（ホスト）。
struct TeamSetupOverlay: View {
    enum Mode: Equatable { case coop, versus }

    let session: OnlineSession
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @State private var mode: Mode = .coop
    /// 敵味方に分かれる時、相手チームへ入れる人。
    @State private var redIDs: Set<OnlinePeerID> = []
    @State private var prepared = false

    private var room: OnlineRoom { session.room }
    private var players: [OnlinePeer] {
        let all = room.players
        return all.filter { $0.id == room.hostPeerID } + all.filter { $0.id != room.hostPeerID }
    }
    private var coopAvailable: Bool { players.count <= 5 }
    private var blue: [OnlinePeer] { mode == .coop ? players : players.filter { !redIDs.contains($0.id) } }
    private var red: [OnlinePeer] { mode == .coop ? [] : players.filter { redIDs.contains($0.id) } }
    private var isValid: Bool { (!blue.isEmpty || !red.isEmpty) && blue.count <= 5 && red.count <= 5 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {}
            VStack(spacing: 10) {
                HStack {
                    Text(L("チーム分け", "Teams"))
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.gold)
                    Spacer()
                    Label(L("AI: \(FlowText.difficulty(room.botDifficulty))", "AI: \(FlowText.difficulty(room.botDifficulty))"), systemImage: "cpu")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 10) {
                    modeCard(.coop, symbol: "person.3.fill", title: L("みんなで協力", "Co-op vs AI"),
                             detail: coopAvailable ? L("参加者は全員味方。相手は AI", "Everyone on your team, AI opponents")
                                                   : L("6 人以上は選べません", "Not available for 6+ players"),
                             enabled: coopAvailable)
                    modeCard(.versus, symbol: "figure.fencing", title: L("敵味方に分かれる", "Split teams"),
                             detail: L("自分チームと相手チームに分ける。空き枠は AI", "Split into two teams, AI fills the rest"),
                             enabled: true)
                }
                HStack(alignment: .top, spacing: 8) {
                    teamColumn(.blue, title: L("自分チーム", "Your team"), members: blue)
                    Text("VS")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundStyle(Theme.gold)
                        .padding(.top, 40)
                    teamColumn(.red, title: L("相手チーム", "Enemy team"), members: red)
                }
                Text(mode == .versus ? L("名前をタップするとチームを入れ替えます", "Tap a name to switch teams")
                                     : L("空いた枠は AI が入ります", "AI fills the empty slots"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 12) {
                    Button {
                        FlowFX.back(app)
                        onClose()
                    } label: {
                        Text(L("戻る", "Back")).frame(minWidth: 90)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("team_setup_back")
                    Button {
                        decide()
                    } label: {
                        Label(L("決定（ヒーロー選択へ）", "Confirm (pick heroes)"), systemImage: "checkmark.circle.fill")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.5)
                    .accessibilityIdentifier("team_setup_confirm")
                }
            }
            .padding(16)
            .frame(maxWidth: 660)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 20)
        }
        .onAppear(perform: prepare)
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        mode = coopAvailable ? .coop : .versus
        // 敵味方: ホストから順に交互（自分チーム → 相手チーム → …）
        redIDs = Set(players.enumerated().filter { $0.offset % 2 == 1 }.map(\.element.id))
    }

    private func modeCard(_ m: Mode, symbol: String, title: String, detail: String, enabled: Bool) -> some View {
        let selected = mode == m
        return Button {
            guard enabled else { return }
            FlowFX.tap(app)
            mode = m
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(selected ? Color.black : Theme.cyan)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.heading(15)).foregroundStyle(selected ? Color.black : Theme.textPrimary)
                    Text(detail).font(Theme.body(10)).foregroundStyle(selected ? Color.black.opacity(0.7) : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.black) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.gold : Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.white.opacity(0.8) : Theme.panelStroke, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(m == .coop ? "team_mode_coop" : "team_mode_versus")
    }

    private func teamColumn(_ team: Team, title: String, members: [OnlinePeer]) -> some View {
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        return VStack(spacing: 4) {
            Text(title)
                .font(Theme.heading(13))
                .foregroundStyle(color)
            ForEach(0..<5, id: \.self) { i in
                if i < members.count {
                    memberRow(members[i], color: color)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu").font(.system(size: 11))
                        Text("AI").font(Theme.body(12))
                        Spacer()
                    }
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.45), lineWidth: 1))
        .opacity(members.count > 5 ? 0.7 : 1)
        .overlay(alignment: .bottom) {
            if members.count > 5 {
                Text(L("5 人までです", "Max 5 players"))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.danger)
                    .offset(y: 14)
            }
        }
    }

    private func memberRow(_ peer: OnlinePeer, color: Color) -> some View {
        Button {
            guard mode == .versus else { return }
            FlowFX.tap(app)
            if redIDs.contains(peer.id) { redIDs.remove(peer.id) } else { redIDs.insert(peer.id) }
        } label: {
            HStack(spacing: 6) {
                if peer.id == room.hostPeerID {
                    Image(systemName: "house.fill").font(.system(size: 10)).foregroundStyle(Theme.gold)
                }
                Text(peer.name)
                    .font(Theme.heading(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if mode == .versus {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("team_member_\(peer.id)")
    }

    private func decide() {
        guard isValid else { return }
        FlowFX.confirm(app)
        session.arrangeTeams(blue: blue.map(\.id), red: red.map(\.id))
        onClose()
    }
}
