import SwiftUI
import VelstriaCore

// 担当: 統合（契約）

/// 戦闘の起動元の文脈（アプリ内のみ。sim / replay には載せない）。
enum BattleContext: Equatable {
    case normal
    /// ライジングのステージ（終了後にブラケットを進める）。
    case rising(stageIndex: Int)
}

/// 観戦の初期設定（観戦の準備画面・設定から。観戦者にだけ効く）。
struct SpectatorOptions: Codable, Equatable {
    /// 再生速度（BattleController.spectatorSpeeds のいずれか。オンラインでは無視）。
    var speed: Double = 1
    /// 視界（nil = 全体が見える、.blue / .red = そのチームの視界）。
    var vision: Team?
    /// 自動カメラ（nil = 既定: AI 同士の観戦・観戦席はオン、リプレイはオフ）。
    var director: Bool?
}

/// 戦闘の起動パラメータ。
struct BattleLaunch: Identifiable, Equatable {
    let id = UUID()
    var config: MatchConfig
    /// リプレイ再生の場合に設定（入力は replay から供給）。
    var replay: ReplayData?
    /// ランク戦などで結果をランクに反映するか。
    var countsForRank: Bool = false
    /// 起動元の文脈（ライジング等）。
    var context: BattleContext = .normal
    /// オンライン対戦: 自分の座席（config.players の添字）。nil ならオフライン（または観戦席）。
    var onlineSeat: Int?
    /// オンライン対戦を観戦席で見る（座席なし。ホストの配信を遅延付きで再生する）。
    var onlineSpectator: Bool = false
    /// オンライン対戦: 試合を始めた時の座席ごとの参加者（config.players の添字 → プレイヤー ID・フレンドコード）。
    /// リザルトの通報・ブロックの相手を、名前ではなく座席で引く（同じ名前の参加者・試合中に抜けた参加者を取り違えない）。
    var onlineSeatPlayers: [Int: OnlineSeatPlayer] = [:]
    /// リプレイの持ち主の座席（config.players の添字）。nil なら最初の人間の枠。
    var replayOwnerSeat: Int?
    /// 観戦の初期設定（速度・視界・自動カメラ）。
    var spectatorOptions = SpectatorOptions()

    /// 観戦者として見る（操作なし・霧は観戦者の選んだ視点・報酬なし）。
    /// AI 同士の観戦、リプレイ、オンラインの観戦席、人間のいないオフライン構成（全 AI のカスタムなど）。
    var isSpectating: Bool {
        config.mode == .spectate || replay != nil || onlineSpectator || isAllBotsOffline
    }
    /// 人間の枠が 1 つもないオフライン構成。
    var isAllBotsOffline: Bool {
        onlineSeat == nil && !onlineSpectator && !config.players.isEmpty
            && config.players.allSatisfy { $0.controller == .bot }
    }
    var isOnline: Bool { onlineSeat != nil || onlineSpectator }
    /// 自分のチーム（オンラインは座席、オフラインは唯一の人間。観戦者は nil）。
    var localTeam: Team? {
        if isSpectating { return nil }
        if let seat = onlineSeat, config.players.indices.contains(seat) { return config.players[seat].team }
        return config.humanSlot?.team
    }
    /// リプレイの持ち主の座席（リプレイ以外は nil）。
    var ownerSeat: Int? {
        guard replay != nil else { return nil }
        if let s = replayOwnerSeat, config.players.indices.contains(s) { return s }
        return config.players.firstIndex { $0.controller == .human }
    }
}

/// オンライン対戦の座席に座っていた参加者（試合の開始時に部屋の状態から控える）。
struct OnlineSeatPlayer: Equatable {
    var peerID: OnlinePeerID
    var friendCode: String?

    /// 座席（config.players の添字と同じ番号）に座っている人間の参加者。名前は照らし合わせない
    /// （クライアントの部屋の名前は表示用に整えてあり、試合の構成の名前と一致しないことがある）。
    static func capture(room: OnlineRoom, players: [PlayerSlot]) -> [Int: OnlineSeatPlayer] {
        var result: [Int: OnlineSeatPlayer] = [:]
        // 座席の並び = config.players の並び（OnlineRoom.seatIndex(of:) と同じ数え方）
        for (i, seat) in room.seats.enumerated() where players.indices.contains(i) && players[i].controller == .human {
            guard let id = seat.peerID else { continue }
            result[i] = OnlineSeatPlayer(peerID: id, friendCode: room.peer(id)?.friendCode)
        }
        return result
    }
}

/// マジックチェスの起動パラメータ。
struct MagicChessLaunch: Identifiable, Equatable {
    let id = UUID()
    var config: MagicChessConfig
}

/// 戦闘の終了結果。
struct BattleOutcome: Equatable {
    var launch: BattleLaunch
    var summary: MatchSummary
    var replay: ReplayData?
    /// 途中離脱（練習場の退出など）。
    var abandoned: Bool
}

/// アプリ全体の状態。`@Environment(AppModel.self)` で参照する。
@Observable
@MainActor
final class AppModel: FriendProfileAccess {
    let master = MasterData.shared
    let router = Router()
    let persistence: PersistenceService
    let storeKit: StoreKitService
    let audio: AudioService
    let haptics: HapticsService
    /// フレンド（申請・在席・パーティの招待）。FeatureFlags.lanMatch が有効な時だけ受信箱へ繋ぐ。
    let friends = FriendHub()
    /// 公開の名刺（relay の Directory）とランキング（第3段）。
    let publicProfiles = PublicProfileService()
    let ranking = RankingService()

    var profile: Profile {
        didSet {
            guard profile != oldValue else { return }
            if profile.settings.language != oldValue.settings.language {
                Loc.current = Loc.resolve(profile.settings.language)
            }
            if profile.settings != oldValue.settings {
                audio.apply(settings: profile.settings)
                haptics.enabled = profile.settings.hapticsEnabled
            }
            persistence.scheduleSave(profile)
            // オンボーディングを終えたら受信箱へ繋ぐ
            if profile.onboardingCompleted, !oldValue.onboardingCompleted { friends.start() }
        }
    }

    /// 起動中の戦闘（ルートで fullScreenCover 表示）。
    var activeBattle: BattleLaunch?
    /// 起動中のマジックチェス（ルートで fullScreenCover 表示）。
    var activeMagicChess: MagicChessLaunch?
    /// 参加中のオンライン対戦の部屋（ロビー〜戦闘〜リザルトの間保持。退出で nil）。
    var online: OnlineSession?
    /// 直近の戦闘結果と報酬（リザルト画面用）。
    var lastOutcome: BattleOutcome?
    var lastRewardReport: RewardReport?
    /// トースト表示用メッセージ。
    var toast: String?
    /// オンラインのルールに同意する前に開かれたリンク（招待・フレンド）。同意したら開き直す。
    @ObservationIgnored private var pendingOnlineLink: URL?
    /// 規則を満たさない名前の知らせを、この起動で出したか。
    @ObservationIgnored private var notedReplacedOnlineName = false

    init(persistence: PersistenceService = PersistenceService()) {
        self.persistence = persistence
        var loaded = persistence.loadProfile() ?? Profile()
        TesterAccess.applyIfUnlocked(to: &loaded, master: MasterData.shared)
        self.profile = loaded
        self.storeKit = StoreKitService()
        self.audio = AudioService()
        self.haptics = HapticsService()
        Loc.current = Loc.resolve(loaded.settings.language)
        audio.apply(settings: loaded.settings)
        haptics.enabled = loaded.settings.hapticsEnabled
        storeKit.attach(to: self)
        wireFriends()
        wirePublicServices()
    }

    /// 公開の名刺・ランキング（第3段）: 送る・読むのはクラウドのランクと同じ条件（オンラインに同意した 13 歳以上）。
    private func wirePublicServices() {
        publicProfiles.isAllowed = { [weak self] in self?.syncsCloudRank ?? false }
        publicProfiles.own = { [weak self] in self?.ownPublicCard() }
        ranking.isAllowed = { [weak self] in self?.syncsCloudRank ?? false }
        ranking.myCode = { [weak self] in self?.profile.friendCode }
        ranking.friendCodes = { [weak self] in self?.profile.friends.map(\.code) ?? [] }
    }

    /// 自分の名刺の中身（名前は外に見せる形。得意ヒーロー 3 体は使った試合の多い順）。
    func ownPublicCard() -> (code: String, key: String, card: PublicCardPayload)? {
        let p = profile
        guard FriendCode.isValid(p.friendCode), FriendInboxKey.isValid(p.inboxKey) else { return nil }
        let heroes = DraftShowcase.favorites(p, roster: master.heroes.map(\.heroID), limit: 3).map { id -> PublicHeroStat in
            let c = p.career.perHero[id] ?? HeroCareer()
            return PublicHeroStat(heroID: id, matches: c.matches, wins: min(c.wins, c.matches))
        }
        let avatar: String? = master.hero(p.avatarHeroID) != nil ? p.avatarHeroID : nil
        let card = PublicCardPayload(name: String(onlineName.prefix(12)), avatar: avatar, frame: p.equippedAvatarFrame,
                                     level: max(1, p.accountLevel), country: p.countryCode.flatMap(CountryFlag.normalized),
                                     heroes: heroes, matches: p.career.matches, wins: min(p.career.wins, p.career.matches))
        return (p.friendCode, p.inboxKey, card)
    }

    /// 運営のメールを取りに行き、まだ入れていない物をメールに入れる（起動時・前面に戻った時。オンラインに同意した時だけ通信する）。
    func refreshOpsMail() async {
        guard syncsCloudRank, let mail = await OpsMailService.fetch(base: OnlineRelayConfig.baseURL, transport: rankTransport) else { return }
        var p = profile
        OpsMailService.merge(mail, into: &p)
        if p != profile { profile = p }
    }

    private func wireFriends() {
        friends.host = self
        friends.isBusy = { [weak self] in self?.activeBattle != nil || self?.activeMagicChess != nil }
        friends.onNotice = { [weak self] text in self?.showToast(text) }
        friends.onJoinParty = { [weak self] invite in self?.joinPartyRoom(code: invite.room) }
    }

    /// 起動時処理（ログインボーナス・デイリー更新・未処理トランザクション）。
    func onLaunch(now: Date = Date()) {
        LiveOpsService.onLaunch(profile: &profile, master: master, now: now)
        // ランクのシーズン: 新しいシーズンの最初の起動でランクを下げ、前のシーズンの報酬をメールで送る（クラウドへ預ける前に）
        SeasonService.refresh(profile: &profile, now: now)
        Task { await storeKit.start() }
        friends.start()
        Task {
            await pullCloudRank()
            await publicProfiles.publishOwn()
            await refreshOpsMail()
        }
    }

    // MARK: ランク（クラウド）

    /// クラウドのランクの通信の送り手（テストは差し替える）。
    @ObservationIgnored var rankTransport: RankCloud.Transport = FriendInboxEraser.urlSession

    /// クラウドのランクを使うか: オンライン機能のルールに同意した 13 歳以上だけ（フレンドの受信箱と同じ条件。OnlineAccess）。
    /// 使わない間はフレンドコード・鍵・勝敗を中継サーバーへ送らず、ランクは端末の計算（RankService.apply）だけで進める。
    /// フレンドサーバーを止めている間（friends.isEnabled。単体テスト）も送らない。
    var syncsCloudRank: Bool { onlineAccess == .available && friends.isEnabled() }

    /// 起動時・オンラインのルールに同意した時: クラウドのランクを取り込む（初回は端末の記録を預ける）。
    func pullCloudRank() async {
        guard syncsCloudRank else { return }
        let code = profile.friendCode, key = profile.inboxKey
        // 同意を取り消した後に端末で進めた: 中継の古いランクを消してから、端末のランクを預け直す（消せなければ今回は預けない。
        // 残したまま預けると、中継は記録のあるアカウントの seed を受け取らず、古いランクに戻してしまう）
        if profile.cloudRankStale {
            guard await RankCloud.erase(code: code, key: key, transport: rankTransport), profile.friendCode == code else { return }
            profile.cloudRankStale = false
            publicProfiles.forgetPublished()
        }
        if let s = await RankCloud.seed(code: code, key: key, local: profile.rank, transport: rankTransport) { adoptCloudRank(s, code: code) }
    }

    /// ランク戦の結果をクラウドへ送り、正の値で端末の写しを上書きする（クラウドのランクを使わない間は送らない）。
    private func syncRankedMatch(_ outcome: BattleOutcome, report: RewardReport) {
        guard syncsCloudRank else { return }
        let code = profile.friendCode, key = profile.inboxKey, transport = rankTransport
        let matchID = "m_" + String(RankService.stableHash("\(profile.playerID)|\(outcome.summary.seed)|\(outcome.summary.duration)"), radix: 36)
        let won = report.won, rating = report.matchRating, mvp = outcome.summary.humanPlayer?.isMVP == true
        Task {
            if let s = await RankCloud.match(code: code, key: key, matchID: matchID, won: won, rating: rating, mvp: mvp, transport: transport) {
                adoptCloudRank(s, code: code)
            }
        }
    }

    /// クラウドの値で端末のランクを上書きし、中継にこのコードのデータがあると記録する（全データの削除で中継のランクも消す。
    /// FriendHub.hasServerData）。待っている間にデータを削除した（コードが変わった）なら何もしない。
    private func adoptCloudRank(_ s: CloudRank, code: String) {
        guard profile.friendCode == code else { return }
        var p = profile
        p.rank.adopt(s)
        p.inboxRegistered = true
        profile = p
    }

    // MARK: 戦闘

    func startBattle(_ launch: BattleLaunch) {
        router.isMatchFlowPresented = false
        friends.declineAllAsBusy()
        activeBattle = launch
    }

    // MARK: オンライン対戦

    /// 部屋を作る（ホスト）。既に参加中なら先に退出する。LAN の待ち受け（Bonjour / IP 直結）と、
    /// インターネットの中継（部屋コード。違う場所・違う Wi-Fi の相手）の両方を開く。
    /// relayCode: 決めた部屋コード（-relayCode。自動検証用）。nil なら作る。
    func hostOnlineRoom(name roomName: String? = nil, port: UInt16? = OnlineProtocol.defaultPort,
                        relay: Bool = true, relayCode: String? = nil) {
        leaveOnlineRoom()
        let name = onlineName
        let session = OnlineSession.host(peerID: profile.playerID, name: name,
                                         roomName: roomName ?? L("\(name) の部屋", "\(name)'s room"),
                                         avatar: profile.avatarHeroID, friendCode: profile.friendCode)
        wire(session)
        session.startListening(preferredPort: port)
        if relay { session.startRelay(baseURL: OnlineRelayConfig.baseURL, code: relayCode) }
        online = session
    }

    /// 部屋コードで入る（中継経由。違う場所・違う Wi-Fi のホストへ）。code は正規化済み（RelayRoomCode.parse）。
    func joinOnlineRoom(relayCode code: String, wantsSpectate: Bool = false) {
        joinOnlineRoom(connection: RelayGuestConnection(code: code, baseURL: OnlineRelayConfig.baseURL), wantsSpectate: wantsSpectate)
    }

    /// 招待リンク（velstria://join?code=XXXXXX[&spectate=1]）を開いた: 部屋コードで参加し、オンラインの画面へ移る。
    /// このアプリの招待リンクなら true（扱えなかった時はトーストで理由を出す）。
    @discardableResult
    func openOnlineJoinLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == OnlineJoinLink.scheme else { return false }
        guard FeatureFlags.lanMatch else { return true }
        guard let link = OnlineJoinLink(url: url) else {
            showToast(L("招待リンクの部屋コードが正しくありません", "The invite link has an invalid room code"))
            return true
        }
        guard profile.onboardingCompleted else {
            showToast(L("はじめの設定を終えてから、もう一度リンクを開いてください", "Finish the first-time setup, then open the link again"))
            return true
        }
        guard activeBattle == nil, activeMagicChess == nil else {
            showToast(L("試合中は参加できません。試合が終わってからリンクを開いてください", "You are in a match. Open the link again after it ends"))
            return true
        }
        if deferUntilOnlineAllowed(url) { return true }
        if let online {
            if online.role == .client, online.joinedRelayCode == link.code, online.isConnected {
                // 既にその部屋にいる: 画面を出すだけ
                showOnlineLobby()
                return true
            }
            if online.isHost, online.connectedPeerCount > 1 {
                // 参加者のいる部屋を黙って閉じない
                showToast(L("自分の部屋を閉じてから参加してください", "Close your own room before joining another"))
                showOnlineLobby()
                return true
            }
        }
        joinOnlineRoom(relayCode: link.code, wantsSpectate: link.spectate)
        showOnlineLobby()
        return true
    }

    /// フレンドのリンク（velstria://friend?code=XXXXXXXX&name=…）を開いた: その相手へフレンド申請を送る。
    /// このアプリのフレンドのリンクなら true（扱えなかった時はトーストで理由を出す）。招待リンクより先に判定する。
    @discardableResult
    func openFriendLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == OnlineJoinLink.scheme else { return false }
        let action = (url.host ?? url.pathComponents.first { $0 != "/" } ?? "").lowercased()
        guard action == "friend" else { return false }
        guard FeatureFlags.lanMatch else { return true }
        guard let link = FriendLink(url: url) else {
            showToast(L("フレンドコードが正しくありません", "The friend link has an invalid code"))
            return true
        }
        guard profile.onboardingCompleted else {
            showToast(L("はじめの設定を終えてから、もう一度リンクを開いてください", "Finish the first-time setup, then open the link again"))
            return true
        }
        if deferUntilOnlineAllowed(url) { return true }
        friends.start()
        switch friends.requestFriend(code: link.code) {
        case .sent, .accepted: break
        case .alreadyFriend: showToast(L("すでにフレンドです", "You are already friends"))
        case .isSelf: showToast(L("自分のフレンドコードです", "That is your own friend code"))
        case .blocked: showToast(FriendHub.blockedMessage)
        case .invalid(let message): showToast(message)
        }
        return true
    }

    /// パーティを作る: 部屋を作って自分が先に座る（フレンドは同じチームに入る）。すでに自分の部屋があればそのまま使う。
    func hostPartyRoom() {
        guard FeatureFlags.lanMatch, activeBattle == nil, activeMagicChess == nil else { return }
        guard onlineAccess == .available else {
            showOnlineLobby()
            return
        }
        if let online, online.isHost {
            showOnlineLobby()
            return
        }
        let name = onlineName
        hostOnlineRoom(name: L("\(name) のパーティ", "\(name)'s party"))
        online?.takeSeat(0)
        showOnlineLobby()
    }

    /// オンラインの画面を開いた: 部屋に入っていなければ自分のパーティ（部屋）を作る（フレンドをすぐ招待できるように）。
    func ensurePartyRoom() {
        guard FeatureFlags.lanMatch, onlineAccess == .available, online == nil, activeBattle == nil, activeMagicChess == nil else { return }
        noteReplacedOnlineNameIfNeeded()
        let name = onlineName
        hostOnlineRoom(name: L("\(name) のパーティ", "\(name)'s party"))
    }

    /// いま招待に使える部屋（自分がホストで中継が開いている、または部屋コードで入っている）。
    var partyInviteRoom: (code: String, name: String)? {
        guard let session = online else { return nil }
        if session.isHost {
            guard let code = session.relayCode, session.relayStatus?.isReady == true else { return nil }
            return (code, session.room.name)
        }
        guard let code = session.joinedRelayCode, session.isConnected else { return nil }
        return (code, session.room.name)
    }

    /// フレンドをパーティへ招待する。部屋がまだ無ければ作り、部屋コードが使えるようになるまで（最大 10 秒）待ってから送る。
    func inviteToParty(_ friend: Friend) {
        if partyInviteRoom == nil && online == nil { ensurePartyRoom() }
        Task { @MainActor in
            for _ in 0..<40 {
                if let room = partyInviteRoom {
                    friends.invite(friend, roomCode: room.code, roomName: room.name)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            showToast(L("部屋の準備ができませんでした。もう一度お試しください", "The room is not ready. Please try again"))
        }
    }

    /// フレンドの招待に同意した: 部屋コードで入り、ホストと同じチームの空席に自動で座る。
    func joinPartyRoom(code: String) {
        guard FeatureFlags.lanMatch, onlineAccess == .available, RelayRoomCode.isValid(code) else { return }
        guard activeBattle == nil, activeMagicChess == nil else {
            showToast(L("試合中は参加できません", "You are in a match"))
            return
        }
        if let online {
            if online.role == .client, online.joinedRelayCode == code, online.isConnected {
                showOnlineLobby()
                return
            }
            if online.isHost, online.connectedPeerCount > 1 {
                showToast(L("自分の部屋を閉じてから参加してください", "Close your own room before joining another"))
                showOnlineLobby()
                return
            }
        }
        joinOnlineRoom(relayCode: code)
        online?.seatsWithHostTeam = true
        showOnlineLobby()
    }

    private func showOnlineLobby() {
        router.isMatchFlowPresented = false
        if router.path.last != .onlineLobby { router.path = [.onlineLobby] }
    }

    /// 部屋に入る（クライアント）。wantsSpectate: 観戦席で入る（試合中なら途中から観戦する）。
    func joinOnlineRoom(connection: OnlineConnection, wantsSpectate: Bool = false) {
        leaveOnlineRoom()
        noteReplacedOnlineNameIfNeeded()
        let name = onlineName
        let session = OnlineSession.join(peerID: profile.playerID, name: name, connection: connection, wantsSpectate: wantsSpectate,
                                         avatar: profile.avatarHeroID, friendCode: profile.friendCode)
        wire(session)
        online = session
    }

    private func wire(_ session: OnlineSession) {
        session.onMatchStart = { [weak self, weak session] config, seat in
            guard let self, let session else { return }
            guard let seat, config.players.indices.contains(seat) else {
                // 座席の無い開始（起こらないはず）: ホストが試合を回さないと部屋全体が止まるので、実況として開く（B1 の保険）
                if session.isHost { session.onSpectateStart?(config) }
                return
            }
            if self.activeBattle != nil {
                if session.isHost {
                    // ホストが試合を回せない（起こらないはず）: 全員を待たせないよう部屋をロビーに戻す
                    session.matchEnded(aborted: true)
                } else {
                    // 別の戦闘中（練習場など）に開始の合図が来た: 進行中の戦闘は守り、自分の枠は AI に任せる
                    session.declineMatch()
                }
                self.showToast(L("オンライン対戦が始まりましたが、戦闘中のため参加できませんでした", "The online match started while you were in another battle"))
                return
            }
            var p = self.profile
            p.lastPickedHeroID = config.players[seat].heroID
            self.profile = p
            self.startBattle(BattleLaunch(config: config, onlineSeat: seat,
                                          onlineSeatPlayers: OnlineSeatPlayer.capture(room: session.room, players: config.players)))
        }
        // 観戦（観戦席の参加者・座らずに実況するホスト）: 操作なし・報酬なしの観戦の戦闘を開く
        session.onSpectateStart = { [weak self, weak session] config in
            guard let self, let session else { return }
            if self.activeBattle != nil {
                if session.isHost {
                    session.matchEnded(aborted: true)
                } else {
                    session.declineSpectate()
                }
                self.showToast(L("観戦が始まりましたが、戦闘中のため開けませんでした", "Spectating started while you were in another battle"))
                return
            }
            self.startBattle(BattleLaunch(config: config, onlineSpectator: true,
                                          onlineSeatPlayers: OnlineSeatPlayer.capture(room: session.room, players: config.players)))
        }
        session.onDisconnected = { [weak self] reason in
            self?.showToast(reason)
        }
        session.onNotice = { [weak self] text in
            self?.showToast(text)
        }
        // 観戦の案内を受ける前に、戦闘（読み込み・リザルトを含む）を開いているかを聞く（開いていれば何も変えずに断る）
        session.isBattleOpen = { [weak self] in self?.activeBattle != nil }
        // ホスト: ブロックした相手は部屋に入れない
        session.blockedFriendCodes = { [weak self] in Set(self?.profile.blockedPlayers.map(\.code) ?? []) }
    }

    // MARK: オンラインの安全（ガイドライン 1.2 / 5.1）

    /// オンライン機能を使えるか（ルールへの同意・年齢）。
    var onlineAccess: OnlineAccess { OnlineAccess.status(for: profile) }

    /// 他のプレイヤーへ見せる自分の名前（規則を満たさない古い名前は送らない）。
    var onlineName: String {
        profile.displayName.isEmpty ? L("プレイヤー", "Player") : PlayerNameRules.outgoing(profile.displayName)
    }

    /// オンラインのルール（コミュニティガイドライン・利用規約）に同意した: 受信箱へ繋ぎ、クラウドのランクを取り込み、待たせていたリンクを開く。
    func acceptOnlineRules() {
        guard onlineAccess == .needsConsent else { return }
        profile.acceptedOnlineRulesVersion = FeatureFlags.currentOnlineRulesVersion
        friends.start()
        // ランク戦の結果を送る前に端末のランクを預ける（預けずに送ると、中継は初期のランクから数え始める）。名刺も送る
        Task {
            await pullCloudRank()
            await publicProfiles.publishOwn()
            await refreshOpsMail()
        }
        if let url = pendingOnlineLink {
            pendingOnlineLink = nil
            if !openFriendLink(url) { openOnlineJoinLink(url) }
        }
    }

    /// オンライン機能をやめる（同意を取り消す）: 部屋を出て受信箱を切る（クラウドのランクも送らなくなる）。次にオンラインを開くと同意し直す。
    func revokeOnlineRules() {
        leaveOnlineRoom()
        friends.reset()
        pendingOnlineLink = nil
        profile.acceptedOnlineRulesVersion = 0
        // 中継のランクと名刺（ランクの消去で名刺も消える）を消す。消せなければ、次に同意した時に預け直す前に消す（cloudRankStale）
        publicProfiles.forgetPublished()
        guard profile.inboxRegistered else { return }
        profile.cloudRankStale = true
        let code = profile.friendCode, key = profile.inboxKey, transport = rankTransport
        Task {
            if await RankCloud.erase(code: code, key: key, transport: transport), profile.friendCode == code {
                profile.cloudRankStale = false
            }
        }
    }

    /// オンラインを使えない時のリンク: 同意がまだなら同意の画面を出し、同意したら開き直す。年齢で使えなければ知らせる。
    /// 先へ進めないなら true。
    private func deferUntilOnlineAllowed(_ url: URL) -> Bool {
        switch onlineAccess {
        case .available:
            return false
        case .needsConsent:
            pendingOnlineLink = url
            showOnlineLobby()
            return true
        case .ageRestricted:
            showToast(OnlineAccess.ageRestrictedMessage)
            return true
        case .disabled:
            return true
        }
    }

    /// ブロックする（フレンドコード単位）。自分がホストの部屋にいれば、その相手を部屋から外す。
    func blockPlayer(_ target: PlayerReportTarget) {
        if let code = target.friendCode { friends.block(code: code, name: target.name) }
        removeFromHostedRoom(target)
        showToast(L("\(target.displayName) をブロックしました", "Blocked \(target.displayName)"))
    }

    /// 自分がホストの部屋から外す（この部屋には入り直せない）。
    func kickFromRoom(_ target: PlayerReportTarget) {
        guard removeFromHostedRoom(target) else { return }
        showToast(L("\(target.displayName) を部屋から外しました", "Removed \(target.displayName) from the room"))
    }

    @discardableResult
    private func removeFromHostedRoom(_ target: PlayerReportTarget) -> Bool {
        guard let session = online, session.isHost else { return false }
        let ids = session.room.peers.filter { p in
            p.id != session.localPeerID
                && ((target.peerID != nil && p.id == target.peerID) || (target.friendCode != nil && p.friendCode == target.friendCode))
        }.map(\.id)
        for id in ids { session.kick(id) }
        return !ids.isEmpty
    }

    /// 全データの削除の前に: 部屋を出て、フレンドの受信箱を切る（新しいフレンドコードで繋ぎ直すまで古いコードで繋がない）。
    func prepareForDataDeletion() {
        leaveOnlineRoom()
        friends.reset()
        pendingOnlineLink = nil
    }

    /// オンライン機能をやめて、中継サーバーの受信箱も消す（新しいフレンドコードになり、フレンドの一覧は空になる）。
    /// completion(false) は通信の失敗（同意は取り消したまま。もう一度試せる）。
    func revokeOnlineRulesAndEraseServerData(completion: @escaping @MainActor (Bool) -> Void) {
        revokeOnlineRules()
        friends.eraseServerData(completion: completion)
    }

    /// オンラインを開いた時: 保存している名前が規則を満たさず「プレイヤー」と表示されるなら、一度だけ知らせる。
    func noteReplacedOnlineNameIfNeeded() {
        guard !notedReplacedOnlineName, PlayerNameRules.isReplacedOnline(profile.displayName) else { return }
        notedReplacedOnlineName = true
        showToast(L("今の名前はほかのプレイヤーには「プレイヤー」と表示されます。プロフィールで名前を変えてください",
                    "Other players see your current name as \"Player\". Change it in your profile"))
    }

    func leaveOnlineRoom() {
        online?.leave()
        online = nil
    }

    /// 戦闘終了時に BattleSessionView から呼ばれる。報酬を適用しリザルト用に保持する。
    @discardableResult
    func completeBattle(_ outcome: BattleOutcome, now: Date = Date()) -> RewardReport {
        var p = profile
        var report = RewardService.apply(outcome: outcome, to: &p, master: master, persistence: persistence, now: now)
        // 報酬の対象外の試合（観戦・カスタム・オンライン）のリプレイ保存と、観戦・リプレイの視聴記録（報酬なし）
        ReplayArchiveService.process(outcome: outcome, report: &report, profile: &p, persistence: persistence, master: master, now: now)
        profile = p
        lastOutcome = outcome
        lastRewardReport = report
        if report.rankAfter != nil { syncRankedMatch(outcome, report: report) }
        // 名刺の通算の成績が変わった（送ってよい時だけ。変わっていなければ送らない）
        Task { await publicProfiles.publishOwn() }
        return report
    }

    func dismissBattle() {
        activeBattle = nil
        #if DEBUG || TESTER_TOOLS
        FXCheckSession.shared.battleDismissed(app: self)
        #endif
        // 観戦席: 戦闘中に断った次の試合の観戦を、閉じた後に求め直す
        online?.battleClosed()
    }

    // MARK: マジックチェス

    func startMagicChess(_ launch: MagicChessLaunch) {
        router.isMatchFlowPresented = false
        friends.declineAllAsBusy()
        activeMagicChess = launch
    }

    func dismissMagicChess() {
        activeMagicChess = nil
    }

    // MARK: 便利

    func showToast(_ message: String) {
        toast = message
    }

    /// ゲームに出すヒーロー（HeroRoster）は全員が使える（解放・所持の制限なし。2026-10-12）。
    func owns(heroID: String) -> Bool { EconomyService.isOwned(heroID: heroID, profile: profile) }
    func owns(cosmeticID: String) -> Bool { profile.ownedCosmeticIDs.contains(cosmeticID) }
}
