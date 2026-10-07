import Foundation
import Observation

// 担当: online。フレンドの状態と手順（申請・承認・在席・パーティの招待と返事）。画面は FriendsView / PartyInviteOverlay。
//
// - 受信箱（FriendInboxClient）で、フレンドからの申請・招待・返事を受ける。差出人のコードは中継が付けるのでなりすませない。
// - フレンド申請: コードかリンクで相手へ申請 → 相手が承認すると相互にフレンドになる。お互いに申請した場合はすぐ成立する。
//   相手が不在でも申請は中継が預かり、繋いだ時に渡る。フレンドでない相手からの招待は無視する（迷惑対策）。
// - パーティ: ホストの部屋（部屋コード）へフレンドを招待する。招待された側は 拒否 / 待って（30 秒後に参加）/ 同意 を選ぶ。
//   同意すると部屋へ入り、ホストと同じチームの空席に自動で座る（OnlineSession.seatsWithHostTeam）。残りの席は AI。
// - 在席: 繋がっている間 20 秒ごとにフレンドの在席を問い合わせる。

/// フレンドの保存先（AppModel の profile）。テストは差し替える。
@MainActor
protocol FriendProfileAccess: AnyObject {
    var profile: Profile { get set }
}

/// 承認待ちの申請（相手から届いた）。
struct FriendRequest: Equatable, Identifiable {
    var code: String
    var name: String
    var id: String { code }
}

/// 届いているパーティの招待。
struct PartyInvite: Equatable, Identifiable {
    var id = UUID()
    /// 招待した人のフレンドコード。
    var from: String
    var name: String
    /// 部屋コード・部屋の名前。
    var room: String
    var roomName: String
    var receivedAt: Date
}

@Observable
@MainActor
final class FriendHub {
    /// 受信箱の状態。
    private(set) var status: FriendInboxClient.Status = .offline
    /// いま繋がっているフレンドのコード。
    private(set) var onlineCodes: Set<String> = []
    /// 承認待ちの申請。
    private(set) var incomingRequests: [FriendRequest] = []
    /// 画面に出している招待（返事を待っている）。
    private(set) var pendingInvite: PartyInvite?

    @ObservationIgnored weak var host: FriendProfileAccess?
    /// 試合中など、招待を受けられない。
    @ObservationIgnored var isBusy: () -> Bool = { false }
    /// 招待に同意した（AppModel が部屋へ入る）。
    @ObservationIgnored var onJoinParty: ((PartyInvite) -> Void)?
    /// お知らせ（トースト用）。
    @ObservationIgnored var onNotice: ((String) -> Void)?
    /// 機能が有効か（公開版では隠す）。
    @ObservationIgnored var isEnabled: () -> Bool = { FeatureFlags.lanMatch }
    @ObservationIgnored var now: () -> Date = { Date() }

    @ObservationIgnored private let baseURL: () -> URL
    @ObservationIgnored private let makeSocket: RelaySocketFactory
    @ObservationIgnored private let schedule: RelayScheduler
    @ObservationIgnored private var client: FriendInboxClient?
    @ObservationIgnored private var inviteQueue: [PartyInvite] = []
    /// 「しばらく拒否」を選んだ相手 → いつまで。
    @ObservationIgnored private var suppressedUntil: [String: Date] = [:]
    /// 在席の問い合わせ・「待って」の予約を捨てるための世代。
    @ObservationIgnored private var presenceToken = 0
    @ObservationIgnored private var waitToken = 0

    static let presenceInterval: TimeInterval = 20
    static let waitSeconds = 30
    static let suppressSeconds: TimeInterval = 300
    /// 古い招待は捨てる（部屋がもう無いかもしれない）。
    static let inviteLifetime: TimeInterval = 120
    static let maxIncomingRequests = 20
    static let maxQueuedInvites = 5
    static let maxFriends = 100
    static let maxOutgoingRequests = 50

    init(baseURL: @escaping () -> URL = { OnlineRelayConfig.baseURL },
         makeSocket: @escaping RelaySocketFactory = RelayDefaults.socketFactory,
         schedule: @escaping RelayScheduler = RelayDefaults.scheduler) {
        self.baseURL = baseURL
        self.makeSocket = makeSocket
        self.schedule = schedule
    }

    // MARK: - 状態の読み取り

    var friends: [Friend] { host?.profile.friends ?? [] }
    var myCode: String { host?.profile.friendCode ?? "" }
    var myName: String {
        let name = PlayerNameRules.normalized(host?.profile.displayName ?? "")
        return name.isEmpty ? L("プレイヤー", "Player") : name
    }
    var isOnline: Bool { status == .online }

    func friend(code: String) -> Friend? { friends.first { $0.code == code } }
    func isFriendOnline(_ code: String) -> Bool { onlineCodes.contains(code) }

    // MARK: - 接続

    /// 受信箱へ繋ぐ（アプリが前面に来た時・オンボーディングを終えた時）。機能が無効・未設定なら何もしない。
    func start() {
        guard isEnabled(), let host, host.profile.onboardingCompleted,
              FriendCode.isValid(host.profile.friendCode), FriendInboxKey.isValid(host.profile.inboxKey) else { return }
        if let client, client.code != host.profile.friendCode {
            client.stop()
            self.client = nil
        }
        let active = self.client ?? makeClient(code: host.profile.friendCode, key: host.profile.inboxKey)
        self.client = active
        active.start()
    }

    /// 切る（アプリが裏へ回った時）。
    func stop() {
        presenceToken += 1
        client?.stop()
        onlineCodes = []
    }

    private func makeClient(code: String, key: String) -> FriendInboxClient {
        let c = FriendInboxClient(baseURL: baseURL(), code: code, key: key, makeSocket: makeSocket, schedule: schedule)
        c.onStatus = { [weak self] status in self?.statusChanged(status) }
        c.onMessage = { [weak self] from, payload in self?.handle(from: from, payload: payload) }
        c.onPresence = { [weak self] online in self?.onlineCodes = Set(online) }
        return c
    }

    private func statusChanged(_ new: FriendInboxClient.Status) {
        status = new
        if new == .online {
            resendOutgoingRequests()
            refreshPresence()
            presenceLoop()
        } else {
            onlineCodes = []
        }
    }

    /// フレンドの在席を今すぐ問い合わせる。
    func refreshPresence() {
        client?.requestPresence(friends.map(\.code))
    }

    private func presenceLoop() {
        presenceToken += 1
        let token = presenceToken
        schedule(Self.presenceInterval) { [weak self] in
            guard let self, self.presenceToken == token, self.status == .online else { return }
            self.refreshPresence()
            self.presenceLoop()
        }
    }

    // MARK: - フレンド申請

    enum AddResult: Equatable {
        /// 申請を送った（相手が承認すると成立する）。
        case sent
        /// 相手からの申請があったので、そのまま成立した。
        case accepted
        case alreadyFriend
        case isSelf
        case invalid(String)
    }

    /// コード（リンクの貼り付けも可）でフレンド申請する。
    @discardableResult
    func requestFriend(input: String) -> AddResult {
        switch FriendCode.parse(input) {
        case .failure(let e): return .invalid(e.message)
        case .success(let code): return requestFriend(code: code)
        }
    }

    @discardableResult
    func requestFriend(code: String) -> AddResult {
        guard FriendCode.isValid(code) else { return .invalid(FriendCode.InputError.invalid(code).message) }
        guard code != myCode else { return .isSelf }
        guard friend(code: code) == nil else { return .alreadyFriend }
        // 相手からの申請が届いている: 承認として扱う
        if let request = incomingRequests.first(where: { $0.code == code }) {
            approve(request)
            return .accepted
        }
        mutate { p in
            if !p.outgoingFriendRequests.contains(code) {
                p.outgoingFriendRequests.append(code)
                if p.outgoingFriendRequests.count > Self.maxOutgoingRequests { p.outgoingFriendRequests.removeFirst() }
            }
        }
        sendRequest(to: code, notify: true)
        return .sent
    }

    private func sendRequest(to code: String, notify: Bool) {
        client?.send(to: code, payload: InboxPayload(.friendRequest, name: myName), queue: true) { [weak self] result in
            guard notify, let self else { return }
            switch result {
            case .delivered, .queued:
                self.onNotice?(L("フレンド申請を送りました。承認されるとフレンドになります", "Friend request sent. You become friends once they accept"))
            case .offline:
                self.onNotice?(L("申請を送れませんでした。少し待ってからもう一度お試しください", "Could not send the request. Please try again shortly"))
            case .notConnected:
                self.onNotice?(L("フレンドサーバーに繋がっていません。繋がると申請を送ります", "Not connected to the friend server. The request will be sent once connected"))
            }
        }
    }

    /// 返事待ちの申請を送り直す（繋がった時。相手が不在でも中継が預かり、同じ申請は 1 通にまとまる）。
    private func resendOutgoingRequests() {
        for code in host?.profile.outgoingFriendRequests ?? [] where friend(code: code) == nil {
            sendRequest(to: code, notify: false)
        }
    }

    /// 届いた申請を承認する。
    func approve(_ request: FriendRequest) {
        incomingRequests.removeAll { $0.code == request.code }
        makeFriends(code: request.code, name: request.name)
        client?.send(to: request.code, payload: InboxPayload(.friendAccept, name: myName), queue: true)
    }

    /// 届いた申請を無視する（相手には知らせない）。
    func ignore(_ request: FriendRequest) {
        incomingRequests.removeAll { $0.code == request.code }
    }

    /// フレンドを外す（相手のフレンド一覧には残る。招待は相手から無視される）。
    func removeFriend(code: String) {
        mutate { p in p.friends.removeAll { $0.code == code } }
        onlineCodes.remove(code)
    }

    private func makeFriends(code: String, name: String) {
        let clean = FriendNames.clean(name)
        var isNew = false
        mutate { p in
            p.outgoingFriendRequests.removeAll { $0 == code }
            if let i = p.friends.firstIndex(where: { $0.code == code }) {
                if !clean.isEmpty { p.friends[i].name = clean }
            } else if p.friends.count < Self.maxFriends {
                p.friends.append(Friend(code: code, name: clean.isEmpty ? FriendNames.display("") : clean, addedAt: now()))
                isNew = true
            }
        }
        if isNew {
            onNotice?(L("\(FriendNames.display(clean)) とフレンドになりました", "You are now friends with \(FriendNames.display(clean))"))
            refreshPresence()
        }
    }

    // MARK: - パーティ

    /// フレンドをパーティ（部屋）へ招待する。
    func invite(_ friend: Friend, roomCode: String, roomName: String) {
        guard RelayRoomCode.isValid(roomCode) else {
            onNotice?(L("部屋の準備ができてから招待してください", "Invite after the room is ready"))
            return
        }
        let name = FriendNames.display(friend.name)
        client?.send(to: friend.code, payload: InboxPayload(.partyInvite, name: myName, room: roomCode, roomName: roomName)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .delivered:
                self.onNotice?(L("\(name) を招待しました", "Invited \(name)"))
            case .queued, .offline:
                self.onNotice?(L("\(name) はオフラインです", "\(name) is offline"))
            case .notConnected:
                self.onNotice?(L("フレンドサーバーに繋がっていません", "Not connected to the friend server"))
            }
        }
    }

    enum InviteResponse: Equatable {
        case accept
        case decline(suppress: Bool)
        /// 少し待ってから参加する（waitSeconds 秒後）。
        case wait
    }

    /// 画面の招待への返事。
    func respond(_ response: InviteResponse) {
        guard let invite = pendingInvite else { return }
        pendingInvite = nil
        switch response {
        case .accept:
            reply(to: invite, .accept)
            join(invite)
        case .decline(let suppress):
            reply(to: invite, .decline)
            if suppress { suppressedUntil[invite.from] = now().addingTimeInterval(Self.suppressSeconds) }
        case .wait:
            reply(to: invite, .wait, wait: Self.waitSeconds)
            waitToken += 1
            let token = waitToken
            schedule(TimeInterval(Self.waitSeconds)) { [weak self] in
                guard let self, self.waitToken == token else { return }
                self.join(invite)
            }
        }
        showNextInvite()
    }

    /// 試合を始める時など: 画面の招待を「受けられない」と返して閉じる。
    func declineAllAsBusy() {
        waitToken += 1
        if let invite = pendingInvite { reply(to: invite, .busy) }
        for invite in inviteQueue { reply(to: invite, .busy) }
        pendingInvite = nil
        inviteQueue = []
    }

    private func join(_ invite: PartyInvite) {
        guard !isBusy() else {
            onNotice?(L("試合中のためパーティに参加できませんでした", "Could not join the party during a match"))
            return
        }
        onJoinParty?(invite)
    }

    private func reply(to invite: PartyInvite, _ answer: InboxPayload.Answer, wait: Int? = nil) {
        client?.send(to: invite.from, payload: InboxPayload(.inviteReply, room: invite.room, answer: answer, wait: wait))
    }

    private func showNextInvite() {
        guard pendingInvite == nil else { return }
        while !inviteQueue.isEmpty {
            let next = inviteQueue.removeFirst()
            if now().timeIntervalSince(next.receivedAt) <= Self.inviteLifetime {
                pendingInvite = next
                return
            }
        }
    }

    // MARK: - 受信

    func handle(from code: String, payload: InboxPayload) {
        guard let kind = payload.kind, code != myCode else { return }
        switch kind {
        case .friendRequest:
            handleFriendRequest(from: code, name: payload.name ?? "")
        case .friendAccept:
            // 自分が申請した相手、またはすでにフレンドの名前の更新だけ受け付ける
            if host?.profile.outgoingFriendRequests.contains(code) == true || friend(code: code) != nil {
                makeFriends(code: code, name: payload.name ?? "")
            }
        case .partyInvite:
            handleInvite(from: code, payload: payload)
        case .inviteReply:
            handleReply(from: code, payload: payload)
        }
    }

    private func handleFriendRequest(from code: String, name: String) {
        if friend(code: code) != nil {
            // すでにフレンド（相手が外して申請し直した等）: 承認を返す
            makeFriends(code: code, name: name)
            client?.send(to: code, payload: InboxPayload(.friendAccept, name: myName), queue: true)
            return
        }
        let clean = FriendNames.clean(name)
        if host?.profile.outgoingFriendRequests.contains(code) == true {
            // お互いに申請していた: すぐ成立
            makeFriends(code: code, name: clean)
            client?.send(to: code, payload: InboxPayload(.friendAccept, name: myName), queue: true)
            return
        }
        if let i = incomingRequests.firstIndex(where: { $0.code == code }) {
            incomingRequests[i].name = clean
            return
        }
        guard incomingRequests.count < Self.maxIncomingRequests else { return }
        incomingRequests.append(FriendRequest(code: code, name: clean))
        onNotice?(L("\(FriendNames.display(clean)) からフレンド申請が届きました", "Friend request from \(FriendNames.display(clean))"))
    }

    private func handleInvite(from code: String, payload: InboxPayload) {
        // フレンドでない相手の招待は無視する
        guard let known = friend(code: code), let room = payload.room, RelayRoomCode.isValid(room) else { return }
        let invite = PartyInvite(from: code, name: FriendNames.display(known.name), room: room,
                                 roomName: String((payload.roomName ?? "").prefix(40)), receivedAt: now())
        if let until = suppressedUntil[code], until > now() {
            reply(to: invite, .decline)
            return
        }
        guard !isBusy() else {
            reply(to: invite, .busy)
            return
        }
        if pendingInvite?.from == code {
            // 同じ人からの新しい招待は、いま出しているものと入れ替える
            pendingInvite = invite
        } else if pendingInvite == nil {
            pendingInvite = invite
        } else if inviteQueue.count < Self.maxQueuedInvites {
            inviteQueue.removeAll { $0.from == code }
            inviteQueue.append(invite)
        }
    }

    private func handleReply(from code: String, payload: InboxPayload) {
        guard let known = friend(code: code), let answer = payload.answer.flatMap(InboxPayload.Answer.init(rawValue:)) else { return }
        let name = FriendNames.display(known.name)
        switch answer {
        case .accept:
            onNotice?(L("\(name) が参加します", "\(name) is joining"))
        case .decline:
            onNotice?(L("\(name) は招待を断りました", "\(name) declined the invite"))
        case .wait:
            let seconds = min(max(payload.wait ?? Self.waitSeconds, 1), 120)
            onNotice?(L("\(name) は \(seconds) 秒後に参加します", "\(name) will join in \(seconds)s"))
        case .busy:
            onNotice?(L("\(name) は試合中です", "\(name) is in a match"))
        }
    }

    // MARK: - 内部

    private func mutate(_ body: (inout Profile) -> Void) {
        guard let host else { return }
        var p = host.profile
        body(&p)
        host.profile = p
    }
}
