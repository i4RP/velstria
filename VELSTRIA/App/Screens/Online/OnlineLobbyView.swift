import SwiftUI
import VelstriaCore

// 担当: online。オンライン対戦（リッスンサーバー）の入口と部屋。
// - 入口: 部屋を作る / 同一 LAN の部屋（Bonjour）に入る / アドレスを打って入る
// - 部屋: 座席（Blue 5 / Red 5）に着く → ヒーローを選ぶ → 準備完了 → ホストが開始
// 部屋の状態は AppModel.online（OnlineSession）が持ち、戦闘・リザルトの後もここに戻る。

struct OnlineLobbyView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("オンライン対戦", "Online Match"), showsCurrencies: false) {
            if let session = app.online {
                OnlineRoomView(session: session)
            } else {
                OnlineEntryView()
            }
        }
    }
}

// MARK: - 入口

private struct OnlineEntryView: View {
    @Environment(AppModel.self) private var app
    @State private var browser = NWOnlineBrowser()
    @State private var address = ""
    @State private var roomName = ""
    @State private var rooms: [NWOnlineBrowser.Room] = []

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            hostPanel.frame(width: 300)
            joinPanel.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .onAppear {
            if roomName.isEmpty {
                let name = app.profile.displayName.isEmpty ? L("プレイヤー", "Player") : app.profile.displayName
                roomName = L("\(name) の部屋", "\(name)'s room")
            }
            browser.onChange = { rooms = $0 }
            browser.start()
        }
        .onDisappear { browser.stop() }
    }

    private var hostPanel: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("部屋を作る", "Host a Room"), systemImage: "antenna.radiowaves.left.and.right")
                    .font(Theme.heading(16))
                    .foregroundStyle(Theme.textPrimary)
                Text(L("あなたの iPhone がホスト（サーバー）になります。同じ Wi-Fi の相手が部屋を見つけて参加できます。",
                       "Your iPhone acts as the host (server). Players on the same Wi-Fi can find and join the room."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                TextField(L("部屋の名前", "Room name"), text: $roomName)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.body(14))
                    .accessibilityIdentifier("online_room_name")
                Button {
                    FlowFX.confirm(app)
                    app.hostOnlineRoom(name: roomName.isEmpty ? nil : roomName)
                } label: {
                    Label(L("部屋を作る", "Create Room"), systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("online_host")
                Spacer(minLength: 0)
                let addresses = OnlineNetwork.localIPv4Addresses()
                if !addresses.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("この端末のアドレス", "This device"))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                        Text(addresses.map { "\($0):\(OnlineProtocol.defaultPort)" }.joined(separator: "  "))
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.cyan)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var joinPanel: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("部屋に入る", "Join a Room"), systemImage: "person.2.wave.2.fill")
                    .font(Theme.heading(16))
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
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(rooms) { room in
                                Button {
                                    FlowFX.confirm(app)
                                    app.joinOnlineRoom(connection: NWOnlineConnection(endpoint: room.endpoint))
                                } label: {
                                    HStack {
                                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.cyan)
                                        Text(room.name).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text(L("参加", "Join")).font(Theme.body(12)).foregroundStyle(Theme.gold)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("online_room_\(room.name)")
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                Divider().overlay(Theme.panelStroke)
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
                Text(L("開発中の機能です。ホストの端末が試合を進めるため、ホストが離脱すると試合は終了します。",
                       "Development feature. The host's device runs the match; if the host leaves, the match ends."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - 部屋

struct OnlineRoomView: View {
    let session: OnlineSession
    @Environment(AppModel.self) private var app
    @State private var roleFilter: Role?
    @State private var autoStarted = false

    private var room: OnlineRoom { session.room }
    private var mySeat: OnlineSeat? { session.localSeat }
    private var connected: Bool { session.isConnected }

    var body: some View {
        VStack(spacing: 8) {
            statusBar
            if case .disconnected(let reason) = session.status {
                disconnectedView(reason)
            } else if room.phase != .lobby && mySeat == nil {
                inProgressView
            } else {
                HStack(alignment: .top, spacing: 12) {
                    seatsPanel.frame(width: 330)
                    pickPanel.frame(maxWidth: .infinity)
                    sidePanel.frame(width: 230)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .onChange(of: room) { _, _ in autoPilot() }
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
                if let port = session.listenPort {
                    let addresses = OnlineNetwork.localIPv4Addresses()
                    Text((addresses.first.map { "\($0):\(port)" } ?? L("ポート \(port)", "port \(port)")))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.cyan)
                } else if let err = session.listenError {
                    Text(err).font(Theme.body(11)).foregroundStyle(Theme.danger).lineLimit(1)
                }
            } else if let rtt = session.rtt {
                Text(String(format: "RTT %.0f ms", rtt * 1000))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(L("\(session.connectedPeerCount) 人", "\(session.connectedPeerCount) players"))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
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

    private func disconnectedView(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 36)).foregroundStyle(Theme.danger)
            Text(reason).font(Theme.heading(15)).foregroundStyle(Theme.textPrimary)
            Button {
                FlowFX.back(app)
                app.leaveOnlineRoom()
            } label: {
                Text(L("入口に戻る", "Back")).frame(minWidth: 140)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("online_back")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inProgressView: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.gold)
            Text(L("この部屋は試合中です。終わるまでお待ちください。", "A match is in progress. Please wait for it to finish."))
                .font(Theme.heading(14))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 座席

    private var seatsPanel: some View {
        Panel(padding: 10) {
            HStack(alignment: .top, spacing: 8) {
                teamColumn(.blue)
                teamColumn(.red)
            }
        }
    }

    private func teamColumn(_ team: Team) -> some View {
        let color = Theme.teamColor(team, colorblind: app.profile.settings.colorblindMode)
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: FlowText.teamSymbol(team))
                Text(FlowText.team(team))
            }
            .font(Theme.heading(12))
            .foregroundStyle(color)
            ForEach(room.seats.filter { $0.team == team }) { seat in
                seatCell(seat, color: color)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func seatCell(_ seat: OnlineSeat, color: Color) -> some View {
        let mine = seat.peerID == session.localPeerID
        let free = seat.peerID == nil
        let canSit = room.phase == .lobby && free
        return Button {
            guard canSit else { return }
            FlowFX.tap(app)
            session.takeSeat(seat.index)
        } label: {
            HStack(spacing: 6) {
                if let hero = seat.loadout.heroID, seat.isHuman {
                    HeroPortraitView(heroID: hero, size: 30)
                } else {
                    Image(systemName: seat.isHuman ? "person.fill" : "cpu")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(seat.isHuman ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(seat.isHuman ? seat.name : L("AI", "AI"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(mine ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: FlowText.positionSymbol(seat.position)).font(.system(size: 8))
                        Text(FlowText.position(seat.position)).font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if seat.isHuman {
                    Image(systemName: seat.ready ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(seat.ready ? Theme.success : Theme.textSecondary)
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(mine ? Theme.gold.opacity(0.14) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(mine ? Theme.gold : color.opacity(0.4), lineWidth: mine ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSit)
        .accessibilityLabel("\(FlowText.team(seat.team)) \(FlowText.position(seat.position)) \(seat.isHuman ? seat.name : "AI")")
        .accessibilityIdentifier("online_seat_\(seat.index)")
    }

    // MARK: ピック

    private var pickPanel: some View {
        let seated = mySeat != nil
        let heroes = app.master.heroes.filter { roleFilter == nil || $0.role == roleFilter }
        let taken = room.seats.filter { $0.peerID != nil && $0.peerID != session.localPeerID }.compactMap(\.loadout.heroID)
        return Panel(padding: 10) {
            VStack(spacing: 8) {
                if seated {
                    RoleFilterBar(selection: $roleFilter)
                    HeroPickerGrid(heroes: heroes, cell: { h in
                        HeroGridCell(hero: h, selected: mySeat?.loadout.heroID == h.heroID,
                                     unavailable: taken.contains(h.heroID), unavailableLabel: L("選択済", "Taken"))
                    }, onTap: { h in
                        guard !taken.contains(h.heroID), room.phase == .lobby else { return }
                        FlowFX.tap(app)
                        session.setLoadout(loadout(for: h.heroID))
                    })
                    Text(L("開発中は未所持のヒーローも選べます。", "All heroes are selectable during development."))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "chair.lounge.fill").font(.system(size: 30)).foregroundStyle(Theme.cyan)
                        Text(L("左の座席をタップして着席してください", "Tap a seat on the left to sit down"))
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// プロフィールの保存値（スペル・ルーン・スキン・自動習得）を反映したロードアウト。
    private func loadout(for heroID: String) -> OnlineLoadout {
        let p = app.profile
        var l = OnlineLoadout(heroID: heroID)
        l.spells = MatchFlowModel.sanitizedSpells(p.heroSpells[heroID] ?? p.defaultSpells, master: app.master)
        l.runes = PracticeSetup.runes(profile: p, master: app.master)
        l.skinID = p.equippedSkins[heroID].flatMap { p.ownedCosmeticIDs.contains($0) ? $0 : nil }
        l.autoLevelSkills = p.settings.autoLevelSkills
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
                    Button {
                        FlowFX.confirm(app)
                        if !session.startMatch(master: app.master) {
                            FlowFX.error(app)
                            app.showToast(L("全員のヒーロー選択と準備完了が必要です", "Everyone must pick a hero and be ready"))
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
                    let unseated = room.peers.filter { room.seat(of: $0.id) == nil }
                    if !unseated.isEmpty {
                        Text(L("未着席: \(unseated.map(\.name).joined(separator: ", "))（開始すると観戦もできず待機になります）",
                               "Not seated: \(unseated.map(\.name).joined(separator: ", ")) (they will wait out the match)"))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.danger)
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

    // MARK: 自動操作（-onlineAuto: 2 台のシミュレータでの検証用）

    private func autoPilot() {
        guard DebugLaunch.isEnabled, DebugLaunch.args.contains("-onlineAuto"), room.phase == .lobby,
              session.isConnected, !autoStarted else { return }
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
            let preferredHero = DebugLaunch.value(after: "-hero") ?? app.profile.lastPickedHeroID ?? "H003"
            let hero = app.master.hero(preferredHero) != nil && !taken.contains(preferredHero)
                ? preferredHero : (app.master.heroes.first { !taken.contains($0.heroID) }?.heroID ?? "H001")
            session.setLoadout(loadout(for: hero))
            return
        }
        if !seat.ready {
            session.setReady(true)
            return
        }
        // 接続している全員が着席・準備完了してから開始する（接続直後の参加者を置き去りにしない）
        let everyoneReady = room.peers.allSatisfy { room.seat(of: $0.id)?.ready == true }
        if session.role == .host, room.canStart, room.peers.count >= 2, everyoneReady {
            autoStarted = true
            session.startMatch(master: app.master)
        }
    }
}
