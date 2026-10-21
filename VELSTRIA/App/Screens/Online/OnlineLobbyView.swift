import SwiftUI
import VelstriaCore

// 担当: online。オンライン対戦（リッスンサーバー）の画面の切り替えと、ピック以降の部屋。
// - パーティ（PartyLobbyView）: 画面を開くと自分のパーティ（部屋）を作る。右パネルでフレンドの招待・申請、近くの部屋、部屋コード。
//   ホストが「ゲーム開始」→ チーム分け（全員味方 / 敵味方に分かれる）→ ピックの段階へ。
// - 部屋（ピック）: 座席（Blue 5 / Red 5）でヒーローを選ぶ → 準備完了 → ホストが開始。ホストはパーティへ戻せる。
// - 観戦: 座らずに観戦席へ移ると、試合開始で観戦画面が開く（遅延付き）。試合中に入った・抜けた人は「観戦する」。
//   ホストは観戦の許可・遅延を決め、座らずに実況（キャスター）として開始することもできる。
// 部屋の状態は AppModel.online（OnlineSession）が持ち、戦闘・リザルトの後もここに戻る（試合の後はパーティへ戻る）。

struct OnlineLobbyView: View {
    @Environment(AppModel.self) private var app
    /// フレンドの画面（ピックの段階の部屋から開く）。
    @State private var showsFriends = false

    var body: some View {
        switch app.onlineAccess {
        case .available:
            lobby
        case .needsConsent:
            // 初回（またはルールの改定後）: コミュニティガイドライン・利用規約に同意してから部屋を作る（ガイドライン 1.2）
            OnlineRulesConsentView()
        case .ageRestricted, .disabled:
            OnlineUnavailableView()
        }
    }

    private var lobby: some View {
        Group {
            if let session = app.online, Self.showsRoom(session) {
                OnlineRoomView(session: session, onShowFriends: { showsFriends = true })
            } else {
                // パーティ（メンバー集め）: 部屋に入っていなければ自分のパーティを作る
                PartyLobbyView()
            }
        }
        .sheet(isPresented: $showsFriends) {
            FriendsView().environment(app)
        }
        .onAppear { app.audio.playMusic(.lobby) }
        .onDisappear {
            // 試合へ進まずに抜けたらホームの曲へ戻す
            if app.activeBattle == nil { app.audio.playMusic(.menu) }
        }
    }

    /// 座席の画面（ピック・試合中・切断）を出すか。ロビーのパーティの段階はパーティの画面。
    static func showsRoom(_ session: OnlineSession) -> Bool {
        if case .disconnected = session.status { return true }
        return session.room.isPicking || session.room.phase != .lobby || session.isSittingOutMatch
    }
}

// MARK: - 部屋コードで参加（中継経由）

/// 部屋コードの入力と「観戦」「参加」（パーティの右パネルの「コード」タブ）。
struct OnlineCodeJoinSection: View {
    @Environment(AppModel.self) private var app
    /// 部屋コードの入力（RelayRoomCode.cleaned で大文字・区切りなし・6 文字まで）。
    @State private var codeInput = ""
    @State private var joinAsSpectator = false

    var body: some View { codeJoinSection }


    private var parsedCode: Result<String, RelayRoomCode.InputError> { RelayRoomCode.parse(codeInput) }

    private var codeJoinSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("部屋コードで参加", "Join by Room Code"), systemImage: "globe.asia.australia.fill")
                .font(Theme.heading(16))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                TextField("", text: $codeInput, prompt: Text("ABC DEF").foregroundStyle(Theme.textSecondary.opacity(0.5)))
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.gold)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.join)
                    .onSubmit { joinByCode() }
                    .onChange(of: codeInput) { _, v in
                        let cleaned = RelayRoomCode.cleaned(v)
                        if cleaned != v { codeInput = cleaned }
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: 110, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(codeHasError ? Theme.danger : Theme.panelStroke, lineWidth: 1))
                    .accessibilityLabel(L("部屋コード", "Room code"))
                    .accessibilityIdentifier("online_code_field")
                Button {
                    FlowFX.tap(app)
                    joinAsSpectator.toggle()
                } label: {
                    Label(L("観戦", "Watch"), systemImage: joinAsSpectator ? "eye.fill" : "eye.slash")
                        .font(Theme.body(12))
                        .foregroundStyle(joinAsSpectator ? Color.black : Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(joinAsSpectator ? Theme.cyan : Color.white.opacity(0.08)))
                        .overlay(Capsule().stroke(Theme.panelStroke, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("観戦で参加", "Join as spectator"))
                .accessibilityValue(joinAsSpectator ? L("オン", "On") : L("オフ", "Off"))
                .accessibilityAddTraits(joinAsSpectator ? .isSelected : [])
                .accessibilityIdentifier("online_code_spectate")
                Button {
                    joinByCode()
                } label: {
                    Text(L("参加", "Join")).frame(minWidth: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .opacity(codeIsValid ? 1 : 0.5)
                .accessibilityIdentifier("online_code_join")
            }
            Text(codeHint)
                .font(Theme.body(11))
                .foregroundStyle(codeHasError ? Theme.danger : Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("online_code_hint")
        }
    }

    private var codeIsValid: Bool { if case .success = parsedCode { return true } else { return false } }

    /// 入力の誤り（使えない文字）。打ちかけ（短い・空）は誤りとして赤くしない。
    private var codeHasError: Bool {
        switch parsedCode {
        case .failure(.ambiguous), .failure(.invalid), .failure(.tooLong): return true
        default: return false
        }
    }

    private var codeHint: String {
        switch parsedCode {
        case .success(let code):
            return joinAsSpectator
                ? L("部屋 \(RelayRoomCode.display(code)) を観戦席で見ます", "Watch room \(RelayRoomCode.display(code)) as a spectator")
                : L("部屋 \(RelayRoomCode.display(code)) に参加します", "Join room \(RelayRoomCode.display(code))")
        case .failure(.empty):
            return L("ホストの画面の 6 文字のコード。違う Wi-Fi・モバイル回線でも参加できます",
                     "The 6-character code on the host's screen. Works across networks and mobile data")
        case .failure(let e):
            return e.message
        }
    }

    private func joinByCode() {
        switch parsedCode {
        case .success(let code):
            FlowFX.confirm(app)
            app.joinOnlineRoom(relayCode: code, wantsSpectate: joinAsSpectator)
        case .failure(let e):
            FlowFX.error(app)
            app.showToast(e.message)
        }
    }
}

// MARK: - 同じ Wi-Fi（Bonjour / アドレス入力）

/// 同じネットワークの部屋の一覧とアドレス入力（パーティの右パネルの「近く」タブ）。
struct OnlineLANSection: View {
    @Environment(AppModel.self) private var app
    @State private var browser = NWOnlineBrowser()
    @State private var address = ""
    @State private var rooms: [NWOnlineBrowser.Room] = []

    var body: some View {
        lanSection
            .onAppear {
                browser.onChange = { rooms = $0 }
                browser.start()
            }
            .onDisappear { browser.stop() }
    }


    private var lanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("同じ Wi-Fi", "Same Wi-Fi"), systemImage: "wifi")
                .font(Theme.heading(14))
                .foregroundStyle(Theme.textPrimary)
            if rooms.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.cyan)
                    Text(browser.statusText ?? L("同じネットワークの部屋を探しています…", "Looking for rooms on this network…"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(minHeight: 44)
            } else {
                VStack(spacing: 6) {
                    ForEach(rooms) { room in
                        roomRow(room)
                    }
                }
            }
            Text(L("見つからない時はホストのアドレスを入力", "Or enter the host's address"))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                TextField("192.168.1.10:\(OnlineProtocol.defaultPort)", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(14))
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("online_address")
                Button {
                    guard let target = OnlineNetwork.parseAddress(address) else {
                        FlowFX.error(app)
                        app.showToast(L("アドレスの形式が違います", "Invalid address"))
                        return
                    }
                    FlowFX.confirm(app)
                    app.joinOnlineRoom(connection: NWOnlineConnection(host: target.host, port: target.port))
                } label: {
                    Label(L("接続", "Connect"), systemImage: "link")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("online_connect")
            }
            let addresses = OnlineNetwork.localIPv4Addresses()
            if !addresses.isEmpty {
                Text(L("この端末のアドレス: ", "This device: ") + addresses.map { "\($0):\(OnlineProtocol.defaultPort)" }.joined(separator: "  "))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.cyan)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Text(L("同じ Wi-Fi の人なら誰でも、部屋を見つけて参加・観戦できます。迷惑な参加者は、参加者の一覧から部屋から外したりブロックしたりできます。ホストの端末が試合を進めるため、ホストが抜けると試合は終わります。",
                   "Anyone on the same Wi-Fi can find, join and watch your room. Remove or block unwanted players from the member list. The host's device runs the match; if the host leaves, the match ends."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 見つかった部屋: 名前・進行状況・人数と「参加」「観戦」。
    private func roomRow(_ room: NWOnlineBrowser.Room) -> some View {
        HStack(spacing: 8) {
            Image(systemName: room.inMatch ? "play.circle.fill" : "dot.radiowaves.left.and.right")
                .foregroundStyle(room.inMatch ? Theme.gold : Theme.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(room)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(roomSummary(room)).font(Theme.body(10)).foregroundStyle(room.isCompatible ? Theme.textSecondary : Theme.danger)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if room.isCompatible {
                if room.allowsSpectators {
                    Button {
                        FlowFX.confirm(app)
                        app.joinOnlineRoom(connection: NWOnlineConnection(endpoint: room.endpoint), wantsSpectate: true)
                    } label: {
                        Label(L("観戦", "Watch"), systemImage: "eye.fill")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.cyan)
                            .frame(minWidth: 64, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(displayName(room)) を観戦", "Watch \(displayName(room))"))
                    .accessibilityIdentifier("online_watch_\(room.name)")
                }
                Button {
                    FlowFX.confirm(app)
                    app.joinOnlineRoom(connection: NWOnlineConnection(endpoint: room.endpoint))
                } label: {
                    Text(L("参加", "Join"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.gold)
                        .frame(minWidth: 52, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("\(displayName(room)) に参加", "Join \(displayName(room))"))
                .accessibilityIdentifier("online_room_\(room.name)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }

    /// 近くの部屋の名前（同じネットワークの誰でも広告できるので、不適切な名前は隠す）。
    private func displayName(_ room: NWOnlineBrowser.Room) -> String {
        let name = PlayerNameRules.sanitizedRoomName(room.name, maxLength: OnlineProtocol.maxServiceNameBytes)
        return name.isEmpty ? L("部屋", "Room") : name
    }

    private func roomSummary(_ room: NWOnlineBrowser.Room) -> String {
        guard room.isCompatible else { return L("アプリの版が違うため入れません", "Different app version") }
        var parts: [String] = [room.inMatch ? L("試合中", "In match") : L("ロビー", "Lobby")]
        if let n = room.players { parts.append(L("選手 \(n)", "\(n) players")) }
        if let n = room.spectators, n > 0 { parts.append(L("観戦 \(n)", "\(n) watching")) }
        if !room.allowsSpectators { parts.append(L("観戦不可", "No spectators")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 部屋

struct OnlineRoomView: View {
    let session: OnlineSession
    /// フレンドの画面を開く（部屋の上の帯の「招待」）。
    var onShowFriends: (() -> Void)?
    @Environment(AppModel.self) private var app
    @State private var roleFilter: Role?
    @State private var autoStarted = false
    @State private var showsMembers = false
    /// 部屋の画面の幅（iPhone SE の横 667pt では中央の列が細くなりすぎるので座席の列を詰める）。
    @State private var roomWidth: CGFloat = 0
    @State private var showsSkins = false
    @State private var showsPlans = false
    @State private var showsRoomControls = false
    @State private var inviteAfterControls = false
    @State private var showsSpells = false

    private var room: OnlineRoom { session.room }
    private var mySeat: OnlineSeat? { session.localSeat }
    private var connected: Bool { session.isConnected }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 6) {
                    draftHeader
                    if case .disconnected(let reason) = session.status {
                        disconnectedView(reason)
                    } else if session.isSittingOutMatch {
                        inProgressView
                    } else {
                        HStack(spacing: 12) {
                            draftTeam(mySeat?.team ?? .blue)
                                .frame(width: geometry.size.width * 0.18)
                            VStack(spacing: 6) {
                                if mySeat == nil {
                                    unseatedPanel
                                } else if showsSkins, let heroID = mySeat?.loadout.heroID {
                                    draftSkins(heroID)
                                } else {
                                    draftHeroes
                                }
                                draftFooter
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            draftTeam(mySeat?.team == .red ? .blue : .red)
                                .frame(width: geometry.size.width * 0.18)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                if showsPlans, let heroID = mySeat?.loadout.heroID {
                    Color.black.opacity(0.65).ignoresSafeArea()
                        .onTapGesture { showsPlans = false }
                    draftPlans(heroID)
                        .frame(width: geometry.size.width * 0.76, height: geometry.size.height * 0.88)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            GeometryReader { geometry in
                Image("HomeBackdrop").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay(Color(red: 0.01, green: 0.04, blue: 0.12).opacity(0.55))
            }.ignoresSafeArea()
        }
        .foregroundStyle(Theme.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsRoomControls, onDismiss: {
            if inviteAfterControls {
                inviteAfterControls = false
                onShowFriends?()
            }
        }) {
            VStack {
                HStack {
                    Text(L("ルーム", "Room")).font(Theme.heading(18))
                    Spacer()
                    Button(L("閉じる", "Close")) { showsRoomControls = false }
                        .accessibilityIdentifier("online_room_controls_close")
                }
                ScrollView(.horizontal) { statusBar }
                sidePanel
            }.padding(16).background(Theme.panel)
        }
        .sheet(isPresented: $showsSpells) {
            VStack {
                HStack {
                    Text(L("バトルスキル", "Battle Skill"))
                    Spacer()
                    Button(L("閉じる", "Close")) { showsSpells = false }
                }
                BattleSkillPicker(current: mySeat?.loadout.spells.first ?? "BS01") { spell in
                    guard var loadout = mySeat?.loadout else { return }
                    loadout.spells = [spell, SpellLoadoutRules.fixedSpellID]
                    session.setLoadout(loadout)
                    showsSpells = false
                }
            }.padding(16).background(Theme.panel).foregroundStyle(Theme.textPrimary)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
        .onChange(of: room) { _, _ in
            if room.phase != .lobby || mySeat == nil { showsPlans = false; showsSpells = false }
            autoPilot()
        }
        .onAppear { autoPilot() }
    }

    // MARK: 状態

    private var statusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: connected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(connected ? Theme.success : Theme.danger)
            Text(room.name.isEmpty ? L("接続中…", "Connecting…") : room.name)
                .font(Theme.heading(14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(session.role == .host ? L("ホスト", "Host") : L("参加者", "Guest"))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(session.role == .host ? Theme.gold : Theme.cyan))
            if session.role == .host {
                if session.relayCode != nil {
                    // 部屋コード（大きく）・コピー・共有・中継の状態。LAN のアドレスは広い画面だけ並べる（狭い画面はコードの詳細に出す）
                    RelayInviteControls(session: session)
                }
                if session.relayCode == nil || roomWidth >= 760 {
                    lanAddressText
                }
            } else if let rtt = session.rtt {
                Text(String(format: "RTT %.0f ms", rtt * 1000))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if session.isHost, room.phase == .lobby {
                Button {
                    FlowFX.back(app)
                    session.returnToParty()
                } label: {
                    Label(L("パーティへ", "Party"), systemImage: "person.3.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("online_back_to_party")
            }
            if let onShowFriends, room.phase == .lobby {
                Button {
                    FlowFX.tap(app)
                    if showsRoomControls {
                        inviteAfterControls = true
                        showsRoomControls = false
                    } else {
                        onShowFriends()
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("フレンドを招待", "Invite friends"))
                .accessibilityIdentifier("online_invite_friends")
            }
            // 選手・観戦席の人数（タップで一覧）
            Button {
                FlowFX.tap(app)
                showsMembers = true
            } label: {
                HStack(spacing: 8) {
                    Label("\(room.players.count)", systemImage: "person.fill")
                    Label("\(room.spectators.count)", systemImage: "eye.fill")
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("選手 \(room.players.count) 人、観戦席 \(room.spectators.count) 人",
                                  "\(room.players.count) players, \(room.spectators.count) spectators"))
            .accessibilityHint(L("参加者の一覧を開きます", "Shows everyone in the room"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("online_counts")
            .popover(isPresented: $showsMembers) {
                OnlineMembersView(session: session)
                    .presentationCompactAdaptation(.popover)
            }
            if session.resyncCount > 0 {
                Text(L("再同期 \(session.resyncCount)", "resync \(session.resyncCount)"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.danger)
            }
            Button {
                FlowFX.back(app)
                app.leaveOnlineRoom()
            } label: {
                Label(L("退出", "Leave"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("online_leave")
        }
    }

    /// ホストの LAN のアドレス（同じ Wi-Fi の相手が手入力で繋ぐ用）。
    @ViewBuilder
    private var lanAddressText: some View {
        if let port = session.listenPort {
            let addresses = OnlineNetwork.localIPv4Addresses()
            Text((addresses.first.map { "\($0):\(port)" } ?? L("ポート \(port)", "port \(port)")))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.cyan)
                .lineLimit(1)
        } else if let err = session.listenError {
            Text(err).font(Theme.body(11)).foregroundStyle(Theme.danger).lineLimit(1)
        }
    }

    private func disconnectedView(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 36)).foregroundStyle(Theme.danger)
            Text(reason)
                .font(Theme.heading(15))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            HStack(spacing: 10) {
                // 部屋コードで入っていた: 同じコードで入り直せる（ホストが中継に繋ぎ直した後など）
                if let code = session.joinedRelayCode {
                    Button {
                        FlowFX.confirm(app)
                        app.joinOnlineRoom(relayCode: code, wantsSpectate: session.joinedAsSpectator)
                    } label: {
                        Label(L("もう一度参加", "Rejoin"), systemImage: "arrow.clockwise").frame(minWidth: 140)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel(L("部屋コード \(RelayRoomCode.display(code)) にもう一度参加", "Rejoin room \(RelayRoomCode.display(code))"))
                    .accessibilityIdentifier("online_rejoin_code")
                }
                Button {
                    FlowFX.back(app)
                    app.leaveOnlineRoom()
                } label: {
                    Text(L("入口に戻る", "Back")).frame(minWidth: 140)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("online_back")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 試合中で、自分は戦っていない（座っていない・試合から抜けた）: 観戦する / 試合に戻る / 待つ。
    private var inProgressView: some View {
        VStack(spacing: 12) {
            Image(systemName: room.allowsSpectators ? "eye.circle.fill" : "hourglass")
                .font(.system(size: 34))
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            Text(L("この部屋は試合中です", "A match is in progress"))
                .font(Theme.heading(16))
                .foregroundStyle(Theme.textPrimary)
            Text(inProgressDetail)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                if session.canWatchMatch {
                    Button {
                        FlowFX.confirm(app)
                        session.requestSpectate()
                    } label: {
                        Label(L("観戦する", "Watch"), systemImage: "eye.fill").frame(minWidth: 140)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("online_watch")
                }
                if session.canRejoinMatch {
                    Button {
                        FlowFX.confirm(app)
                        session.rejoinMatch()
                    } label: {
                        Label(L("試合に戻る", "Rejoin"), systemImage: "arrow.uturn.backward.circle.fill").frame(minWidth: 140)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("online_rejoin")
                }
            }
            if session.isWatchingMatch {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.cyan)
                    Text(L("観戦の準備をしています…", "Preparing to watch…"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inProgressDetail: String {
        guard room.allowsSpectators else {
            return L("この部屋は観戦できません。試合が終わるまでお待ちください。",
                     "Spectating is disabled in this room. Please wait for the match to finish.")
        }
        var lines: [String] = []
        let delay = Int(room.spectatorDelaySeconds.rounded())
        lines.append(delay > 0 ? L("観戦は \(delay) 秒遅れで配信されます（選手への情報漏れを防ぐため）。",
                                   "Spectating is delayed by \(delay)s to protect the players.")
                               : L("観戦は遅延なしで配信されます。", "Spectating has no delay."))
        let watching = room.watchingCount
        if watching > 0 { lines.append(L("いま \(watching) 人が観戦中です。", "\(watching) watching now.")) }
        if room.hostIsCaster { lines.append(L("ホストが実況しています。", "The host is casting this match.")) }
        if session.canRejoinMatch {
            lines.append(L("観戦すると、この試合には選手として戻れなくなります。", "If you watch, you cannot rejoin this match as a player."))
        } else if session.localSeat != nil && session.watchedCurrentMatch {
            lines.append(L("観戦した試合には選手として戻れません。次の試合をお待ちください。",
                           "You watched this match, so you cannot rejoin it. Wait for the next match."))
        }
        return lines.joined(separator: "\n")
    }

    /// 座っていない時: 着席の案内か観戦席（実況）の説明と、観戦席の一覧・切り替え。
    private var unseatedPanel: some View {
        let isSpectator = session.localRole == .spectator
        let isHost = session.role == .host
        let spectators = room.spectators
        return VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: isSpectator ? (isHost ? "mic.circle.fill" : "eye.circle.fill") : "chair.lounge.fill")
                .font(.system(size: 30))
                .foregroundStyle(isSpectator ? Theme.gold : Theme.cyan)
                .accessibilityHidden(true)
            Text(unseatedTitle(isSpectator: isSpectator, isHost: isHost))
                .font(Theme.heading(14))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(unseatedDetail(isSpectator: isSpectator, isHost: isHost))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            if room.allowsSpectators || isHost {
                let title = spectatorToggleTitle(isSpectator: isSpectator, isHost: isHost)
                let symbol = isSpectator ? "chair.lounge" : (isHost ? "mic.fill" : "eye.fill")
                Button {
                    FlowFX.tap(app)
                    session.setSpectator(!isSpectator)
                } label: {
                    // 中央の列は iPhone SE で 80pt 前後まで細くなる: 横並びが入らなければ アイコンの下に 2 行まで の形にする
                    ViewThatFits(in: .horizontal) {
                        Label(title, systemImage: symbol)
                            .font(Theme.heading(14))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                        VStack(spacing: 2) {
                            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                            Text(title)
                                .font(Theme.heading(12))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 6)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(room.phase != .lobby)
                .accessibilityLabel(title)
                .accessibilityIdentifier(isHost ? "online_caster" : "online_spectate_toggle")
            }
            if !spectators.isEmpty {
                VStack(spacing: 4) {
                    Text(L("観戦席 \(spectators.count)/\(OnlineProtocol.maxSpectators)", "Spectators \(spectators.count)/\(OnlineProtocol.maxSpectators)"))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Text(spectators.map(\.name).joined(separator: ", "))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("online_spectator_list")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unseatedTitle(isSpectator: Bool, isHost: Bool) -> String {
        if isSpectator {
            return isHost ? L("実況（キャスター）として観戦します", "You will cast this match")
                          : L("観戦席にいます", "You are a spectator")
        }
        return L("左右の空席をタップして着席してください", "Tap an open seat on either side to sit down")
    }

    private func unseatedDetail(isSpectator: Bool, isHost: Bool) -> String {
        let delay = Int(room.spectatorDelaySeconds.rounded())
        if isSpectator && isHost {
            return L("座らずに試合を回し、遅延なしで全体を見ます。選手が 1 人以上座って準備完了なら開始できます。",
                     "You run the match without playing and see everything live. Start once at least one seated player is ready.")
        }
        if isSpectator {
            return delay > 0 ? L("試合が始まると観戦画面が開きます（\(delay) 秒遅れ）。", "The match opens when it starts (\(delay)s delay).")
                             : L("試合が始まると観戦画面が開きます。", "The match opens when it starts.")
        }
        if !room.allowsSpectators { return L("この部屋は観戦できません。", "Spectating is disabled in this room.") }
        return isHost ? L("ホストは着席するか、実況（座らずに観戦）にすると開始できます。",
                          "As host, sit down or cast (watch without playing) to start.")
                      : L("座らずに観戦席で見ることもできます。", "You can also watch from the spectator seats.")
    }

    private func spectatorToggleTitle(isSpectator: Bool, isHost: Bool) -> String {
        if isSpectator { return isHost ? L("実況をやめる", "Stop Casting") : L("選手に戻る", "Back to Players") }
        return isHost ? L("実況する", "Cast the Match") : L("観戦席に移る", "Move to Spectators")
    }

    /// プロフィールの保存値（スペル・エンブレム・スキン・自動習得）を反映したロードアウト。
    private func loadout(for heroID: String) -> OnlineLoadout {
        let p = app.profile
        var l = OnlineLoadout(heroID: heroID)
        l.spells = SpellLoadoutRules.effective(heroID: heroID, profile: p)
        l.emblem = PracticeSetup.emblem(heroID: heroID, profile: p, master: app.master)
        l.skinID = p.equippedSkins[heroID].flatMap { p.ownedCosmeticIDs.contains($0) ? $0 : nil }
        l.autoLevelSkills = p.settings.autoLevelSkills
        l.buildPlan = p.heroBuildPlans[heroID]
        return l
    }

    // MARK: 右側（準備・開始・ログ）

    private var sidePanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let seat = mySeat {
                    Button {
                        FlowFX.confirm(app)
                        session.setReady(!seat.ready)
                    } label: {
                        Label(seat.ready ? L("準備完了を解除", "Not Ready") : L("準備完了", "Ready"),
                              systemImage: seat.ready ? "xmark.circle" : "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(seat.loadout.heroID == nil || room.phase != .lobby)
                    .opacity(seat.loadout.heroID == nil ? 0.5 : 1)
                    .accessibilityIdentifier("online_ready")
                    Button {
                        FlowFX.tap(app)
                        session.takeSeat(-1)
                    } label: {
                        Label(L("席を立つ", "Leave Seat"), systemImage: "arrow.uturn.left").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(room.phase != .lobby)
                    .accessibilityIdentifier("online_stand")
                }
                if session.role == .host {
                    difficultyPicker
                    spectateSettingsButton
                    Button {
                        FlowFX.confirm(app)
                        if !session.startMatch(master: app.master) {
                            FlowFX.error(app)
                            app.showToast(mySeat == nil && !room.hostIsCaster
                                          ? L("着席するか、実況にしてください", "Sit down or cast the match")
                                          : L("全員のヒーロー選択と準備完了が必要です", "Everyone must pick a hero and be ready"))
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text(L("出撃", "DEPLOY")).font(.system(size: 20, weight: .black, design: .rounded))
                            Text("START").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(2).opacity(0.6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!room.canStart || room.phase != .lobby)
                    .opacity(room.canStart && room.phase == .lobby ? 1 : 0.5)
                    .accessibilityIdentifier("online_start")
                    // 座っていない選手（観戦席・実況のホストを除く）: 試合中は観戦するか待つ
                    let unseated = room.players.filter { room.seat(of: $0.id) == nil && $0.id != room.hostPeerID }
                    if !unseated.isEmpty {
                        Text(room.allowsSpectators
                             ? L("未着席: \(unseated.map(\.name).joined(separator: ", "))（試合中は観戦できます）",
                                 "Not seated: \(unseated.map(\.name).joined(separator: ", ")) (they can watch the match)")
                             : L("未着席: \(unseated.map(\.name).joined(separator: ", "))（試合が終わるまで待機）",
                                 "Not seated: \(unseated.map(\.name).joined(separator: ", ")) (they will wait out the match)"))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                } else {
                    Text(room.canStart ? L("ホストの開始を待っています…", "Waiting for the host to start…")
                                       : L("全員が準備完了になるとホストが開始できます", "The host can start once everyone is ready"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Divider().overlay(Theme.panelStroke)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(session.events.reversed().enumerated()), id: \.offset) { _, line in
                            Text(line).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var difficultyPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("AI の強さ", "AI Difficulty")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 4) {
                ForEach(Difficulty.allCases, id: \.self) { d in
                    Button {
                        FlowFX.tap(app)
                        session.setBotDifficulty(d)
                    } label: {
                        Text(FlowText.difficulty(d))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(room.botDifficulty == d ? .black : Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(Capsule().fill(room.botDifficulty == d ? Theme.gold : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("online_difficulty_\(d.rawValue)")
                }
            }
        }
    }

    // MARK: 観戦の設定（ホスト）

    @State private var showsSpectateSettings = false

    private var spectateSettingsButton: some View {
        Button {
            FlowFX.tap(app)
            showsSpectateSettings = true
        } label: {
            Label(room.allowsSpectators ? L("観戦: \(Int(room.spectatorDelaySeconds.rounded())) 秒遅れ", "Watch: \(Int(room.spectatorDelaySeconds.rounded()))s delay")
                                        : L("観戦: 不可", "Watch: Off"),
                  systemImage: "eye")
                .font(Theme.body(12))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(room.phase != .lobby)
        .accessibilityIdentifier("online_spectate_settings")
        .popover(isPresented: $showsSpectateSettings) {
            OnlineSpectateSettingsView(session: session)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: 自動操作（-onlineAuto: 2 台のシミュレータでの検証用）

    private func autoPilot() {
        guard DebugLaunch.isEnabled, DebugLaunch.args.contains("-onlineAuto"), session.isConnected, !autoStarted else { return }
        // -onlineSpectate: 参加者は観戦席で見る（試合中なら観戦を求める）。ホストは座らずに実況として開始する
        if DebugLaunch.args.contains("-onlineSpectate") {
            if session.role == .client {
                if room.phase == .lobby, session.localRole != .spectator { session.setSpectator(true) }
                if session.canWatchMatch { session.requestSpectate() }
                return
            }
            guard room.phase == .lobby else { return }
            if session.localRole != .spectator {
                session.setSpectator(true)
                return
            }
            let playersReady = room.players.filter { $0.id != room.hostPeerID }
                .allSatisfy { room.seat(of: $0.id)?.ready == true }
            if room.canStart, room.peers.count >= 2, playersReady {
                autoStarted = true
                session.startMatch(master: app.master)
            }
            return
        }
        guard room.phase == .lobby else { return }
        if mySeat == nil {
            // ホストは Blue の mid、参加者は Red の mid（埋まっていれば空席の先頭）
            let preferred = MatchFactory.onlineSeatIndex(team: session.role == .host ? .blue : .red, position: .mid)
            let target = room.seats[preferred].peerID == nil ? preferred : room.seats.first { $0.peerID == nil }?.index
            if let target { session.takeSeat(target) }
            return
        }
        guard let seat = mySeat else { return }
        if seat.loadout.heroID == nil {
            let taken = room.pickedHeroIDs
            let preferredHero = DebugLaunch.value(after: "-hero") ?? app.profile.lastPickedHeroID ?? HeroRoster.defaultHeroID
            let hero = app.master.hero(preferredHero) != nil && !taken.contains(preferredHero)
                ? preferredHero : (app.master.heroes.first { !taken.contains($0.heroID) }?.heroID ?? HeroRoster.defaultHeroID)
            session.setLoadout(loadout(for: hero))
            return
        }
        if !seat.ready {
            session.setReady(true)
            return
        }
        // 接続している選手が全員着席・準備完了してから開始する（接続直後の参加者を置き去りにしない。観戦席は待たない）
        let everyoneReady = room.players.allSatisfy { room.seat(of: $0.id)?.ready == true }
        if session.role == .host, room.canStart, room.peers.count >= 2, everyoneReady {
            autoStarted = true
            session.startMatch(master: app.master)
        }
    }
}

// MARK: - オンラインの選択ステージ

private extension OnlineRoomView {
    var draftHeader: some View {
        HStack {
            Button { showsRoomControls = true } label: {
                Label(L("ルーム", "Room"), systemImage: "slider.horizontal.3")
                    .font(Theme.body(12)).frame(minWidth: 72, minHeight: 44)
            }.accessibilityIdentifier("online_room_controls")
            Spacer()
            VStack(spacing: 1) {
                Text(L("ヒーロー PICK", "HERO PICK")).font(Theme.heading(17))
                Text(room.phase == .lobby
                     ? L("準備完了 \(room.seats.filter { $0.isHuman && $0.ready }.count) / \(room.seats.filter { $0.isHuman }.count)",
                         "Ready \(room.seats.filter { $0.isHuman && $0.ready }.count) / \(room.seats.filter { $0.isHuman }.count)")
                     : L("試合を準備しています…", "Preparing match…"))
                    .font(Theme.body(11)).foregroundStyle(Theme.gold)
            }
            Spacer()
            Button { app.leaveOnlineRoom() } label: {
                Label(L("退出", "Leave"), systemImage: "rectangle.portrait.and.arrow.right")
                    .font(Theme.body(12)).frame(minWidth: 72, minHeight: 44)
            }.accessibilityIdentifier("online_leave")
        }
        .foregroundStyle(Theme.cyan)
    }

    func draftTeam(_ team: Team) -> some View {
        let ally = team == (mySeat?.team ?? .blue)
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        return VStack(spacing: 3) {
            Text(ally ? L("味方", "ALLIES") : L("敵", "ENEMIES"))
                .font(Theme.heading(11)).foregroundStyle(color)
            ForEach(room.seats.filter { $0.team == team }) { seat in
                GeometryReader { geometry in
                    Button {
                        guard seat.peerID == nil, room.phase == .lobby else { return }
                        session.takeSeat(seat.index)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            if let heroID = seat.loadout.heroID, seat.isHuman,
                               let art = PortraitArt.hero(heroID) {
                                Image(uiImage: art).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            } else {
                                color.opacity(0.12)
                                Image(systemName: seat.isHuman ? "person.fill" : "cpu")
                                    .font(.system(size: 24)).foregroundStyle(color.opacity(0.5))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            LinearGradient(colors: [.clear, color.opacity(0.25), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Image(systemName: FlowText.positionSymbol(seat.position))
                                    Text(FlowText.position(seat.position))
                                    Spacer(minLength: 0)
                                    if seat.ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }
                                }.font(Theme.body(9))
                                Text(seat.isHuman ? seat.name : L("AI / 空席", "AI / Open"))
                                    .font(Theme.heading(11)).lineLimit(1)
                                    .foregroundStyle(seat.peerID == session.localPeerID ? Theme.gold : .white)
                            }.padding(5)
                        }
                        .overlay(Rectangle().stroke(seat.peerID == session.localPeerID ? Theme.gold : color.opacity(0.3), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(seat.peerID != nil || room.phase != .lobby)
                    .accessibilityLabel("\(FlowText.team(team)) \(FlowText.position(seat.position)) \(seat.isHuman ? seat.name : "AI")")
                    .accessibilityIdentifier("online_seat_\(seat.index)")
                }
            }
        }
    }

    var draftHeroes: some View {
        let heroes = app.master.heroes.filter { roleFilter == nil || $0.role == roleFilter }
        let taken = room.seats.filter { $0.peerID != nil && $0.peerID != session.localPeerID }.compactMap(\.loadout.heroID)
        return VStack(spacing: 4) {
            RoleFilterBar(selection: $roleFilter)
            GeometryReader { geometry in
                let columns = geometry.size.width > 480 ? 7 : 5
                let size = min(54.0, max(32.0, (geometry.size.width - CGFloat(columns - 1) * 8) / CGFloat(columns)))
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 10) {
                        ForEach(heroes) { hero in
                            let selected = mySeat?.loadout.heroID == hero.heroID
                            Button {
                                guard room.phase == .lobby, !taken.contains(hero.heroID) else { return }
                                FlowFX.tap(app)
                                session.setLoadout(loadout(for: hero.heroID))
                            } label: {
                                VStack(spacing: 3) {
                                    HeroPortraitView(heroID: hero.heroID, size: size, showsRole: false, face: true)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(selected ? Theme.gold : Theme.cyan.opacity(0.4), lineWidth: selected ? 2 : 1))
                                    Text(MasterText.hero(hero)).font(Theme.body(9)).lineLimit(1)
                                }
                                .opacity(taken.contains(hero.heroID) ? 0.3 : 1)
                            }.buttonStyle(.plain)
                                .disabled(taken.contains(hero.heroID) || room.phase != .lobby)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .accessibilityIdentifier("online_pick_\(hero.heroID)")
                        }
                    }.padding(3)
                }.scrollIndicators(.hidden)
            }
        }
    }

    var draftFooter: some View {
        VStack(spacing: 4) {
            if let heroID = mySeat?.loadout.heroID {
                HStack(spacing: 8) {
                    Button { showsPlans = true } label: {
                        Label(L("バトルプラン", "Battle Plan"), systemImage: "list.bullet.rectangle")
                            .font(Theme.body(12)).frame(maxWidth: .infinity, minHeight: 44)
                    }.background(Theme.cyan.opacity(0.12))
                        .overlay(Rectangle().stroke(Theme.cyan.opacity(0.6)))
                        .accessibilityIdentifier("online_battle_plan")
                    Button { showsSpells = true } label: {
                        SpellIconView(spellID: mySeat?.loadout.spells.first ?? "BS01", size: 34)
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel(L("バトルスキルを変更", "Change battle skill"))
                    if let emblem = mySeat?.loadout.emblem {
                        EmblemLoadoutBadge(emblem: emblem, compact: true)
                    }
                }.disabled(room.phase != .lobby)
                .id(heroID)
            }
            HStack(spacing: 8) {
                Button { showsSkins = false } label: {
                    Text(L("ヒーロー", "Heroes")).foregroundStyle(!showsSkins ? Theme.cyan : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button { showsSkins = true } label: {
                    Text(L("スキン", "Skins")).foregroundStyle(showsSkins ? Theme.cyan : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.disabled(mySeat?.loadout.heroID == nil)
                if let seat = mySeat {
                    Button { session.setReady(!seat.ready) } label: {
                        Text(seat.ready ? L("解除", "Unready") : L("準備完了", "Ready"))
                            .font(Theme.heading(12)).frame(minHeight: 36)
                    }.buttonStyle(SecondaryButtonStyle())
                        .disabled(seat.loadout.heroID == nil || room.phase != .lobby)
                        .accessibilityIdentifier("online_ready")
                }
                if session.isHost {
                    Button { session.startMatch(master: app.master) } label: {
                        Text(L("出撃", "Start")).font(Theme.heading(12)).frame(minHeight: 36)
                    }.buttonStyle(PrimaryButtonStyle())
                        .disabled(!room.canStart || room.phase != .lobby)
                        .accessibilityIdentifier("online_start")
                }
            }.font(Theme.body(12)).buttonStyle(.plain)
        }
    }

    func draftSkins(_ heroID: String) -> some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    draftSkin(heroID, skin: nil, height: max(100, geometry.size.height - 12))
                    ForEach(CosmeticInfo.skins(heroID: heroID, master: app.master)) { skin in
                        draftSkin(heroID, skin: skin, height: max(100, geometry.size.height - 12))
                    }
                }.padding(6).frame(minWidth: geometry.size.width)
            }.scrollIndicators(.hidden)
        }
    }

    func draftSkin(_ heroID: String, skin: CosmeticDef?, height: CGFloat) -> some View {
        let owned = skin.map { app.owns(cosmeticID: $0.cosmeticID) } ?? true
        let selected = mySeat?.loadout.skinID == skin?.cosmeticID
        return Button {
            guard owned, var loadout = mySeat?.loadout, loadout.heroID == heroID else { return }
            loadout.skinID = skin?.cosmeticID
            session.setLoadout(loadout)
        } label: {
            ZStack(alignment: .bottom) {
                if let art = skin.flatMap({ PortraitArt.skin($0.cosmeticID) }) ?? PortraitArt.card(heroID) ?? PortraitArt.hero(heroID) {
                    Image(uiImage: art).resizable().scaledToFill()
                        .frame(width: height * 0.64, height: height).clipped()
                }
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                VStack(spacing: 4) {
                    Text(skin.map { MasterText.cosmetic($0) } ?? L("デフォルト", "Default"))
                        .font(Theme.heading(12)).lineLimit(2)
                    Label(selected ? L("使用中", "Equipped") : (owned ? L("使う", "Use") : L("未所持", "Locked")),
                          systemImage: selected ? "checkmark.circle.fill" : (owned ? "paintpalette" : "lock.fill"))
                        .font(Theme.body(10)).foregroundStyle(selected ? Theme.gold : .white)
                }.padding(10)
            }
            .frame(width: height * 0.64, height: height)
            .background(Theme.panel)
            .overlay(Rectangle().stroke(selected ? Theme.gold : Theme.cyan.opacity(0.3), lineWidth: selected ? 2 : 1))
            .opacity(owned ? 1 : 0.55)
        }.buttonStyle(.plain).disabled(!owned || room.phase != .lobby)
            .accessibilityIdentifier("online_skin_\(skin?.cosmeticID ?? "default")")
    }

    func draftPlans(_ heroID: String) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(L("バトルプラン", "Battle Plan")).font(Theme.heading(20))
                Spacer()
                Button { showsPlans = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel(L("閉じる", "Close"))
            }
            Rectangle().fill(Theme.cyan.opacity(0.4)).frame(height: 1)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(BuildRules.plans(for: heroID).enumerated()), id: \.offset) { index, plan in
                        draftPlanRow(heroID, index: index, plan: plan)
                    }
                    if BuildRules.plans(for: heroID).isEmpty {
                        Text(L("このヒーローのプランはありません", "No plans for this hero"))
                    }
                }
            }.scrollIndicators(.hidden)
        }
        .padding(16)
        .background(Color(red: 0.10, green: 0.20, blue: 0.36))
        .overlay(Rectangle().stroke(Theme.cyan.opacity(0.6), lineWidth: 1))
        .accessibilityIdentifier("online_battle_plans")
    }

    func draftPlanRow(_ heroID: String, index: Int, plan: BuildPlan) -> some View {
        let active = ItemSystem.planIndex(heroID: heroID, chosen: mySeat?.loadout.buildPlan) == index
            && (mySeat?.loadout.emblem == nil || mySeat?.loadout.emblem == plan.emblem)
            && (plan.spellHint == nil || mySeat?.loadout.spells.first == plan.spellHint)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(BuildRules.planName(plan)).font(Theme.heading(13))
                Spacer()
                if active {
                    Label(L("有効", "Active"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                } else {
                    Button {
                        guard var loadout = mySeat?.loadout, loadout.heroID == heroID else { return }
                        loadout.buildPlan = index
                        loadout.emblem = plan.emblem
                        if let spell = plan.spellHint { loadout.spells = [spell, SpellLoadoutRules.fixedSpellID] }
                        session.setLoadout(loadout)
                    } label: {
                        Text(L("使う", "Use")).frame(minWidth: 60)
                    }.buttonStyle(PrimaryButtonStyle()).disabled(room.phase != .lobby)
                        .accessibilityIdentifier("online_plan_\(index)_use")
                }
            }.font(Theme.body(12))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    draftPlanItems(plan)
                    draftPlanEmblem(plan)
                }
                VStack(alignment: .leading, spacing: 8) {
                    draftPlanItems(plan)
                    draftPlanEmblem(plan)
                }
            }
        }
        .padding(10)
        .background(active ? Theme.success.opacity(0.13) : Color.white.opacity(0.04))
        .overlay(Rectangle().stroke(active ? Theme.success.opacity(0.55) : Theme.cyan.opacity(0.2)))
    }

    func draftPlanItems(_ plan: BuildPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("ビルド", "Build")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 4) {
                ForEach(Array(plan.items.enumerated()), id: \.offset) { _, itemID in
                    if let item = app.master.item(itemID) { ItemIconView(item: item, size: 32) }
                }
            }
        }
    }

    func draftPlanEmblem(_ plan: BuildPlan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("エンブレム", "Emblems")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                EmblemLoadoutBadge(emblem: plan.emblem, compact: true)
            }
            if let spell = plan.spellHint {
                VStack(spacing: 6) {
                    Text(L("バトルスキル", "Spell")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                    SpellIconView(spellID: spell, size: 32)
                }
            }
        }
    }
}

// MARK: - 部屋コード（ホスト）

/// ホストの部屋コード（大きく）・コピー・共有・中継の状態と再試行。部屋の上の帯に置く。
/// コードをタップすると詳細（説明・状態の理由・LAN のアドレス）を出す。
struct RelayInviteControls: View {
    let session: OnlineSession
    @Environment(AppModel.self) private var app
    @State private var showsDetail = false

    var body: some View {
        if let code = session.relayCode {
            HStack(spacing: 0) {
                Button {
                    FlowFX.tap(app)
                    showsDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            RelayStatusDot(status: session.relayStatus)
                            Text(RelayStatusText.caption(session.relayStatus))
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(RelayStatusText.color(session.relayStatus))
                                .lineLimit(1)
                        }
                        Text(RelayRoomCode.display(code))
                            .font(.system(size: 22, weight: .heavy, design: .monospaced))
                            .foregroundStyle(session.relayStatus?.isReady == true ? Theme.gold : Theme.textSecondary)
                            .fixedSize()
                    }
                    .padding(.horizontal, 4)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("部屋コード \(code.map { String($0) }.joined(separator: " "))", "Room code \(code.map { String($0) }.joined(separator: " "))"))
                .accessibilityValue(RelayStatusText.caption(session.relayStatus))
                .accessibilityHint(L("招待の詳細を開きます", "Shows invite details"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("online_relay_code")
                .popover(isPresented: $showsDetail) {
                    RelayInviteDetailView(session: session)
                        .presentationCompactAdaptation(.popover)
                }
                if case .failed? = session.relayStatus {
                    iconButton("arrow.clockwise", label: L("中継を再試行", "Retry relay"), id: "online_relay_retry") {
                        FlowFX.confirm(app)
                        session.retryRelay()
                    }
                } else {
                    iconButton("doc.on.doc", label: L("部屋コードをコピー", "Copy room code"), id: "online_relay_copy") {
                        FlowFX.tap(app)
                        UIPasteboard.general.string = code
                        app.showToast(L("部屋コードをコピーしました", "Room code copied"))
                    }
                    ShareLink(item: OnlineJoinLink.shareText(code: code, roomName: session.room.name)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("部屋コードを共有", "Share room code"))
                    .accessibilityIdentifier("online_relay_share")
                }
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// 中継の状態の表示（色だけに頼らず、文言と形でも分ける）。
private enum RelayStatusText {
    static func caption(_ status: OnlineRelayStatus?) -> String {
        switch status {
        case .ready?: return L("部屋コード", "ROOM CODE")
        case .connecting?, nil: return L("中継に接続中…", "CONNECTING…")
        case .reconnecting?: return L("再接続中…", "RECONNECTING…")
        case .failed?: return L("中継に接続できません", "RELAY OFFLINE")
        }
    }

    static func color(_ status: OnlineRelayStatus?) -> Color {
        switch status {
        case .ready?: return Theme.success
        case .failed?: return Theme.danger
        default: return Theme.textSecondary
        }
    }

    /// 詳細に出す説明（理由を含む）。
    static func detail(_ status: OnlineRelayStatus?) -> String {
        switch status {
        case .ready?:
            return L("違う場所・違う Wi-Fi の相手も、このコードで参加できます。", "Players on any network can join with this code.")
        case .connecting?, nil:
            return L("中継サーバーに接続しています…", "Connecting to the relay server…")
        case .reconnecting(let reason)?:
            return L("中継サーバーに再接続しています（\(reason)）。同じコードのまま待てます。",
                     "Reconnecting to the relay server (\(reason)). The code stays the same.")
        case .failed(let reason)?:
            return L("中継サーバーに接続できません: \(reason)。同じ Wi-Fi の相手は今まで通り参加できます。",
                     "The relay server is unavailable: \(reason). Players on the same Wi-Fi can still join.")
        }
    }
}

private struct RelayStatusDot: View {
    let status: OnlineRelayStatus?

    var body: some View {
        switch status {
        case .ready?:
            Circle().fill(Theme.success).frame(width: 7, height: 7)
        case .failed?:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(Theme.danger)
        default:
            ProgressView().controlSize(.mini).tint(Theme.cyan).frame(width: 9, height: 9)
        }
    }
}

/// 部屋コードの詳細（大きなコード・説明・状態・再試行・LAN のアドレス）。
private struct RelayInviteDetailView: View {
    let session: OnlineSession
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("友だちを招待", "Invite Players"))
                .font(Theme.heading(15))
                .foregroundStyle(Theme.textPrimary)
            if let code = session.relayCode {
                Text(RelayRoomCode.display(code))
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("online_relay_code_large")
            }
            Text(L("相手はオンラインの「部屋コードで参加」にこのコードを入力するか、共有したリンクを開きます。",
                   "Others enter this code under Online → Join by Room Code, or open the shared link."))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                RelayStatusDot(status: session.relayStatus)
                Text(RelayStatusText.detail(session.relayStatus))
                    .font(Theme.body(12))
                    .foregroundStyle(RelayStatusText.color(session.relayStatus))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if session.relayStatus?.isReady != true {
                Button {
                    FlowFX.confirm(app)
                    session.retryRelay()
                } label: {
                    Label(L("今すぐ再試行", "Retry Now"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("online_relay_retry_detail")
            }
            if let port = session.listenPort, let ip = OnlineNetwork.localIPv4Addresses().first {
                Divider().overlay(Theme.panelStroke)
                Text(L("同じ Wi-Fi: 一覧に表示されます（アドレス \(ip):\(port)）", "Same Wi-Fi: listed automatically (address \(ip):\(port))"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.panel)
    }
}

/// ホストの観戦設定: 観戦の許可・遅延。ロビーでだけ変えられる（試合中に遅延を縮めると意味がなくなる）。
private struct OnlineSpectateSettingsView: View {
    let session: OnlineSession
    @Environment(AppModel.self) private var app

    private var room: OnlineRoom { session.room }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("観戦の設定", "Spectating"))
                .font(Theme.heading(15))
                .foregroundStyle(Theme.textPrimary)
            Toggle(isOn: Binding(get: { room.allowsSpectators }, set: { on in
                FlowFX.tap(app)
                session.setAllowsSpectators(on)
            })) {
                Text(L("観戦を許可する", "Allow spectators"))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.gold)
            .frame(minHeight: 44)
            .accessibilityIdentifier("online_allow_spectators")
            Text(L("観戦の遅延", "Spectator delay"))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                ForEach(OnlineProtocol.spectatorDelayOptions, id: \.self) { seconds in
                    let selected = room.spectatorDelayTicks == OnlineProtocol.ticks(seconds: seconds)
                    Button {
                        FlowFX.tap(app)
                        session.setSpectatorDelay(seconds: seconds)
                    } label: {
                        Text(seconds == 0 ? L("なし", "Off") : L("\(seconds)秒", "\(seconds)s"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? .black : Theme.textPrimary)
                            .frame(minWidth: 52, minHeight: 44)
                            .background(Capsule().fill(selected ? Theme.gold : Color.white.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!room.allowsSpectators)
                    .accessibilityLabel(seconds == 0 ? L("遅延なし", "No delay") : L("\(seconds) 秒遅れ", "\(seconds) second delay"))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("online_delay_\(seconds)")
                }
            }
            .opacity(room.allowsSpectators ? 1 : 0.5)
            Text(L("観戦者は遅れて試合を見ます。選手へ敵の位置を教える不正（ゴースティング）を防ぐため、身内以外の部屋では遅延を付けてください。",
                   "Spectators see the match late. Keep a delay unless everyone is a friend, so spectators cannot tell players where enemies are (ghosting)."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.panel)
    }
}

/// 部屋の参加者の一覧（選手・観戦席）。座っている選手からも観戦席が見えるように、状態バーの人数から開く（パーティの下の帯からも）。
/// 自分以外の行から 通報・ブロック、ホストなら部屋から外す（ガイドライン 1.2）。
struct OnlineMembersView: View {
    let session: OnlineSession
    var source: PlayerReportTarget.Source = .room
    @Environment(AppModel.self) private var app
    @State private var moderation = ModerationPrompt()

    private var room: OnlineRoom { session.room }

    var body: some View {
        let colorblind = app.profile.settings.colorblindMode
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                header(L("選手 \(room.players.count)/\(OnlineProtocol.maxPlayers)", "Players \(room.players.count)/\(OnlineProtocol.maxPlayers)"),
                       symbol: "person.fill")
                ForEach(room.players) { peer in
                    playerRow(peer, colorblind: colorblind)
                }
                if room.hostIsCaster, let host = room.peer(room.hostPeerID) {
                    header(L("実況", "Caster"), symbol: "mic.fill")
                    row(name: host.name, mine: host.id == session.localPeerID, host: true,
                        detail: L("座らずに試合を回す（遅延なし）", "Runs the match without playing (live)"),
                        symbol: "mic.fill", tint: Theme.gold, peer: host)
                }
                if room.allowsSpectators || !room.spectators.isEmpty {
                    header(L("観戦席 \(room.spectators.count)/\(OnlineProtocol.maxSpectators)",
                             "Spectators \(room.spectators.count)/\(OnlineProtocol.maxSpectators)"),
                           symbol: "eye.fill")
                    if room.spectators.isEmpty {
                        Text(L("まだいません", "Nobody yet"))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(room.spectators) { peer in
                        row(name: peer.name, mine: peer.id == session.localPeerID, host: false,
                            detail: peer.isWatching ? L("観戦中", "Watching") : L("待機中", "Waiting"),
                            symbol: peer.isWatching ? "eye.fill" : "eye", tint: peer.isWatching ? Theme.cyan : Theme.textSecondary,
                            peer: peer)
                    }
                } else {
                    header(L("観戦: 不可", "Spectating: Off"), symbol: "eye.slash")
                }
            }
            .padding(14)
        }
        .frame(width: 320)
        .frame(maxHeight: 280)
        .background(Theme.panel)
        .moderationPrompts(moderation)
        .accessibilityIdentifier("online_members")
    }

    /// 通報・ブロックの対象（自分は対象外）。
    private func target(_ peer: OnlinePeer) -> PlayerReportTarget? {
        guard peer.id != session.localPeerID else { return nil }
        return PlayerReportTarget(name: peer.name, friendCode: peer.friendCode, peerID: peer.id, source: source,
                                  roomCode: session.relayCode ?? session.joinedRelayCode)
    }

    private func header(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 4)
    }

    private func playerRow(_ peer: OnlinePeer, colorblind: Bool) -> some View {
        let seat = room.seat(of: peer.id)
        let detail: String
        if let seat {
            var text = "\(FlowText.team(seat.team)) \(FlowText.position(seat.position))"
            if peer.leftMatch { text += L("・抜けた（AI が操作）", " · left (AI playing)") }
            else if peer.isWatching { text += L("・観戦中", " · watching") }
            detail = text
        } else {
            detail = room.phase == .lobby ? L("未着席", "Not seated") : L("試合の終わりを待っています", "Waiting for the match to end")
        }
        return row(name: peer.name, mine: peer.id == session.localPeerID, host: peer.id == room.hostPeerID,
                   detail: detail,
                   symbol: seat.map { FlowText.teamSymbol($0.team) } ?? "chair.lounge",
                   tint: seat.map { Theme.teamColor($0.team, colorblind: colorblind) } ?? Theme.textSecondary,
                   peer: peer)
    }

    private func row(name: String, mine: Bool, host: Bool, detail: String, symbol: String, tint: Color,
                     peer: OnlinePeer? = nil) -> some View {
        HStack(spacing: 8) {
            rowLabel(name: name, mine: mine, host: host, detail: detail, symbol: symbol, tint: tint)
            if let peer, let target = target(peer) {
                PlayerActionsMenu(target: target, prompt: moderation, canKick: session.isHost, size: 16)
            }
        }
    }

    private func rowLabel(name: String, mine: Bool, host: Bool, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(mine ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                    if host {
                        Text(L("ホスト", "Host"))
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Theme.gold))
                    }
                }
                Text(detail)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
