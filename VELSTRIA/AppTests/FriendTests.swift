import XCTest
@testable import VELSTRIA
import VelstriaCore

/// フレンド機能: フレンドコード・リンク・受信箱の符号化、受信箱への接続（FriendInboxClient。偽のソケット）、
/// 申請・承認・招待・返事の手順（FriendHub）、パーティの席の自動選択、保存データの互換。
@MainActor
final class FriendTests: XCTestCase {
    // MARK: - 部品

    /// 受信箱への接続の代役（送ったテキストを覚え、受信・切断を呼び出し側から起こせる）。
    @MainActor
    private final class FakeSocket: RelaySocket {
        let url: URL
        var onOpen: (() -> Void)?
        var onBinary: ((Data) -> Void)?
        var onText: ((String) -> Void)?
        var onClose: ((Int, String) -> Void)?
        var onFailure: ((String) -> Void)?
        var sent: [String] = []
        var closedWith: (code: Int, reason: String)?
        init(url: URL) { self.url = url }
        func connect() {}
        func send(binary: Data) {}
        func send(text: String) { sent.append(text) }
        func close(code: Int, reason: String) { closedWith = (code, reason) }

        func receive(_ text: String) { onText?(text) }
        func serverClose(_ code: Int) { onClose?(code, "") }
        func fail() { onFailure?("down") }

        /// 送った JSON のうち、種類 t のもの。
        func sentJSON(_ type: String) -> [[String: Any]] {
            sent.compactMap { text in
                guard let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], o["t"] as? String == type else { return nil }
                return o
            }
        }
    }

    @MainActor
    private final class Network {
        var sockets: [FakeSocket] = []
        var last: FakeSocket { sockets[sockets.count - 1] }
        var factory: RelaySocketFactory {
            { [unowned self] url in
                let s = FakeSocket(url: url)
                self.sockets.append(s)
                return s
            }
        }
    }

    @MainActor
    private final class StubHost: FriendProfileAccess {
        var profile: Profile
        init() {
            var p = Profile()
            p.onboardingCompleted = true
            p.displayName = "Me"
            profile = p
        }
    }

    private let friendA = "ABCDEFGH"
    private let friendB = "JKMNPQRS"
    private let stranger = "TUVWXYZ2"
    private let roomCode = "QZ7K4P"

    private struct Rig {
        let hub: FriendHub
        let net: Network
        let host: StubHost
        let clock: ManualRelayScheduler
        var notices: Notices
        var joined: Joined
    }

    private final class Notices { var texts: [String] = [] }
    private final class Joined { var invites: [PartyInvite] = [] }

    /// 受信箱に繋ぎ終えた（hello を受けた）ハブ。
    private func makeRig(friends: [String] = [], online: Bool = true) -> Rig {
        let net = Network()
        let clock = ManualRelayScheduler()
        let host = StubHost()
        host.profile.friends = friends.map { Friend(code: $0, name: "F-\($0.prefix(1))", addedAt: Date(timeIntervalSince1970: 0)) }
        let hub = FriendHub(baseURL: { InMemoryRelay.baseURL }, makeSocket: net.factory, schedule: clock.scheduler)
        hub.host = host
        hub.isEnabled = { true }
        let notices = Notices()
        let joined = Joined()
        hub.onNotice = { notices.texts.append($0) }
        hub.onJoinParty = { joined.invites.append($0) }
        hub.start()
        if online { net.last.receive(#"{"t":"hello","code":"\#(host.profile.friendCode)"}"#) }
        return Rig(hub: hub, net: net, host: host, clock: clock, notices: notices, joined: joined)
    }

    private func msg(from code: String, _ payload: String) -> String {
        #"{"t":"msg","from":"\#(code)","m":\#(payload)}"#
    }

    private func invitePayload(room: String? = nil, name: String = "Sender") -> String {
        #"{"k":"partyInvite","name":"\#(name)","room":"\#(room ?? roomCode)","roomName":"Party"}"#
    }

    // MARK: - フレンドコード

    func testGeneratedFriendCodeIsValidAndRandom() {
        let a = FriendCode.generate(), b = FriendCode.generate()
        XCTAssertTrue(FriendCode.isValid(a))
        XCTAssertEqual(a.count, 8)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(FriendInboxKey.isValid(FriendInboxKey.generate()))
        XCTAssertFalse(FriendInboxKey.isValid("short"))
    }

    func testFriendCodeParseNormalizes() {
        XCTAssertEqual(try? FriendCode.parse("abcd efgh").get(), "ABCDEFGH")
        XCTAssertEqual(try? FriendCode.parse("ABCD-EFGH").get(), "ABCDEFGH")
        XCTAssertEqual(try? FriendCode.parse("ＡＢＣＤＥＦＧＨ").get(), "ABCDEFGH")
        XCTAssertEqual(try? FriendCode.parse("velstria://friend?code=ABCDEFGH&name=Taro").get(), "ABCDEFGH")
        XCTAssertEqual(FriendCode.display("ABCDEFGH"), "ABCD EFGH")
    }

    func testFriendCodeParseErrors() {
        XCTAssertEqual(FriendCode.parse("  ").failureValue, .empty)
        XCTAssertEqual(FriendCode.parse("ABCD").failureValue, .tooShort(4))
        XCTAssertEqual(FriendCode.parse("ABCDEFGHJ").failureValue, .tooLong(9))
        XCTAssertEqual(FriendCode.parse("ABCDEFG0").failureValue, .ambiguous("0"))
        XCTAssertEqual(FriendCode.parse("ABCDEFG!").failureValue, .invalid("!"))
        // 部屋コード（6 文字）はフレンドコードとして受け付けない
        XCTAssertEqual(FriendCode.parse(roomCode).failureValue, .tooShort(6))
    }

    func testFriendLinkRoundTripAndRejection() throws {
        let link = FriendLink(code: friendA, name: "Taro")
        let parsed = try XCTUnwrap(FriendLink(url: link.url))
        XCTAssertEqual(parsed, link)
        XCTAssertNil(FriendLink(url: URL(string: "velstria://join?code=ABCDEF")!))
        XCTAssertNil(FriendLink(url: URL(string: "velstria://friend?code=ABC")!))
        XCTAssertNil(FriendLink(url: URL(string: "https://example.com/friend?code=ABCDEFGH")!))
        // 招待リンクはフレンドのリンクとして読まれない（逆も同じ）
        XCTAssertNil(OnlineJoinLink(url: link.url))
    }

    func testFriendNamesAreCleaned() {
        XCTAssertEqual(FriendNames.clean("  Taro\n"), "Taro")
        XCTAssertEqual(FriendNames.clean(String(repeating: "a", count: 40)).count, PlayerNameRules.maxLength)
        XCTAssertEqual(FriendNames.clean("\u{0007}\u{0000}"), "")
    }

    // MARK: - 受信箱のメッセージ

    func testServerMessageDecoding() {
        XCTAssertEqual(InboxServerMessage.decode(#"{"t":"hello","code":"ABCDEFGH"}"#), .hello(code: "ABCDEFGH"))
        XCTAssertEqual(InboxServerMessage.decode(msg(from: friendA, invitePayload())),
                       .message(from: friendA, payload: InboxPayload(.partyInvite, name: "Sender", room: roomCode, roomName: "Party")))
        XCTAssertEqual(InboxServerMessage.decode(#"{"t":"ack","id":3,"result":"queued"}"#), .ack(id: 3, result: .queued))
        XCTAssertEqual(InboxServerMessage.decode(#"{"t":"presence","online":["ABCDEFGH","bad"]}"#), .presence(online: ["ABCDEFGH"]))
        // 差出人が不正・知らない種類・壊れた JSON は読まない
        XCTAssertNil(InboxServerMessage.decode(msg(from: "bad", invitePayload())))
        XCTAssertNil(InboxServerMessage.decode(#"{"t":"other"}"#))
        XCTAssertNil(InboxServerMessage.decode("not json"))
        XCTAssertNil(InboxServerMessage.decode(#"{"t":"ack","id":1,"result":"weird"}"#))
    }

    func testUnknownPayloadKindIsKeptButHasNoKind() throws {
        let decoded = try XCTUnwrap(InboxServerMessage.decode(msg(from: friendA, #"{"k":"futureThing","x":1}"#)))
        guard case .message(_, let payload) = decoded else { return XCTFail("msg のはず") }
        XCTAssertNil(payload.kind)
    }

    func testClientMessageEncoding() throws {
        let text = try XCTUnwrap(InboxClientMessage.send(to: friendA, id: 5, payload: InboxPayload(.friendRequest, name: "Me"), queue: true))
        let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(o["t"] as? String, "send")
        XCTAssertEqual(o["to"] as? String, friendA)
        XCTAssertEqual(o["id"] as? Int, 5)
        XCTAssertEqual(o["queue"] as? Bool, true)
        XCTAssertEqual((o["m"] as? [String: Any])?["k"] as? String, "friendRequest")
        let noQueue = try XCTUnwrap(InboxClientMessage.send(to: friendA, id: 6, payload: InboxPayload(.partyInvite), queue: false))
        XCTAssertNil((try JSONSerialization.jsonObject(with: Data(noQueue.utf8)) as? [String: Any])?["queue"])
    }

    func testInboxURL() {
        let url = OnlineRelayConfig.inboxURL(base: URL(string: "wss://example.com/base/")!, code: friendA, key: "K".padding(toLength: 20, withPad: "k", startingAt: 0))
        XCTAssertEqual(url.path, "/base/v1/inbox/\(friendA)")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "rv" }?.value, "\(OnlineRelayConfig.relayVersion)")
        XCTAssertNotNil(items.first { $0.name == "key" })
    }

    // MARK: - 受信箱への接続

    private func makeClient(_ net: Network, _ clock: ManualRelayScheduler) -> FriendInboxClient {
        FriendInboxClient(baseURL: InMemoryRelay.baseURL, code: friendA, key: "k-0123456789abcdef", makeSocket: net.factory, schedule: clock.scheduler)
    }

    func testClientBecomesOnlineAfterHelloAndSendsWithAck() {
        let net = Network(), clock = ManualRelayScheduler()
        let client = makeClient(net, clock)
        var results: [InboxSendResult] = []
        // 繋ぐ前は送れない
        client.send(to: friendB, payload: InboxPayload(.partyInvite)) { results.append($0) }
        XCTAssertEqual(results, [.notConnected])

        client.start()
        XCTAssertEqual(client.status, .connecting)
        XCTAssertTrue(net.last.url.absoluteString.contains("/v1/inbox/\(friendA)"))
        // hello の前は送れない
        client.send(to: friendB, payload: InboxPayload(.partyInvite)) { results.append($0) }
        XCTAssertEqual(results, [.notConnected, .notConnected])

        net.last.receive(#"{"t":"hello","code":"\#(friendA)"}"#)
        XCTAssertEqual(client.status, .online)
        client.send(to: friendB, payload: InboxPayload(.partyInvite, room: roomCode)) { results.append($0) }
        let sent = net.last.sentJSON("send")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["to"] as? String, friendB)
        net.last.receive(#"{"t":"ack","id":\#(sent[0]["id"] as? Int ?? -1),"result":"delivered"}"#)
        XCTAssertEqual(results.last, .delivered)
    }

    func testClientKeepaliveAndPresenceRequest() {
        let net = Network(), clock = ManualRelayScheduler()
        let client = makeClient(net, clock)
        var presence: [[String]] = []
        client.onPresence = { presence.append($0) }
        client.start()
        net.last.receive(#"{"t":"hello","code":"\#(friendA)"}"#)
        clock.runAll()
        XCTAssertTrue(net.last.sent.contains("ping"))
        client.requestPresence([friendB])
        XCTAssertEqual(net.last.sentJSON("presence").count, 1)
        net.last.receive(#"{"t":"presence","online":["\#(friendB)"]}"#)
        XCTAssertEqual(presence, [[friendB]])
    }

    func testClientReconnectsWithBackoffAndFailsPendingSends() {
        let net = Network(), clock = ManualRelayScheduler()
        let client = makeClient(net, clock)
        client.start()
        net.last.receive(#"{"t":"hello","code":"\#(friendA)"}"#)
        var result: InboxSendResult?
        client.send(to: friendB, payload: InboxPayload(.partyInvite)) { result = $0 }
        net.last.fail()
        XCTAssertEqual(result, .notConnected)
        XCTAssertEqual(client.status, .connecting)
        XCTAssertEqual(net.sockets.count, 1)
        clock.runAll()
        XCTAssertEqual(net.sockets.count, 2, "待ってから繋ぎ直す")
        // 繋がれば待ちの回数が戻る
        net.last.receive(#"{"t":"hello","code":"\#(friendA)"}"#)
        XCTAssertEqual(client.status, .online)
    }

    func testClientGivesUpWhenCodeIsTakenOrVersionIsOld() {
        for (closeCode, expectsFailure) in [(4012, true), (4010, true), (4011, false)] {
            let net = Network(), clock = ManualRelayScheduler()
            let client = makeClient(net, clock)
            client.start()
            net.last.receive(#"{"t":"hello","code":"\#(friendA)"}"#)
            net.last.serverClose(closeCode)
            if expectsFailure {
                guard case .failed = client.status else { return XCTFail("\(closeCode) は諦めるはず") }
            } else {
                XCTAssertEqual(client.status, .offline)
            }
            clock.runAll()
            XCTAssertEqual(net.sockets.count, 1, "\(closeCode) では繋ぎ直さない")
        }
    }

    func testClientStopClosesAndIgnoresLateEvents() {
        let net = Network(), clock = ManualRelayScheduler()
        let client = makeClient(net, clock)
        client.start()
        let socket = net.last
        socket.receive(#"{"t":"hello","code":"\#(friendA)"}"#)
        client.stop()
        XCTAssertEqual(client.status, .offline)
        XCTAssertEqual(socket.closedWith?.code, 1000)
        socket.receive(#"{"t":"hello","code":"\#(friendA)"}"#)
        XCTAssertEqual(client.status, .offline)
        clock.runAll()
        XCTAssertEqual(net.sockets.count, 1)
    }

    // MARK: - ハブ: 申請と承認

    func testHubDoesNotConnectWhenDisabledOrNotOnboarded() {
        let net = Network()
        let clock = ManualRelayScheduler()
        let host = StubHost()
        let hub = FriendHub(baseURL: { InMemoryRelay.baseURL }, makeSocket: net.factory, schedule: clock.scheduler)
        hub.host = host
        hub.isEnabled = { false }
        hub.start()
        XCTAssertTrue(net.sockets.isEmpty, "公開版（機能が無効）では繋がない")
        hub.isEnabled = { true }
        host.profile.onboardingCompleted = false
        hub.start()
        XCTAssertTrue(net.sockets.isEmpty, "はじめの設定の前は繋がない")
    }

    func testRequestFriendSendsQueuedRequestAndTracksOutgoing() throws {
        let rig = makeRig()
        XCTAssertEqual(rig.hub.requestFriend(input: "abcd-efgh"), .sent)
        XCTAssertEqual(rig.host.profile.outgoingFriendRequests, [friendA])
        let sent = try XCTUnwrap(rig.net.last.sentJSON("send").first)
        XCTAssertEqual(sent["to"] as? String, friendA)
        XCTAssertEqual(sent["queue"] as? Bool, true)
        XCTAssertEqual((sent["m"] as? [String: Any])?["k"] as? String, "friendRequest")
        XCTAssertEqual((sent["m"] as? [String: Any])?["name"] as? String, "Me")
        // 同じ相手へ続けても、返事待ちは 1 件
        _ = rig.hub.requestFriend(code: friendA)
        XCTAssertEqual(rig.host.profile.outgoingFriendRequests, [friendA])
    }

    func testRequestFriendRejectsSelfDuplicateAndInvalid() {
        let rig = makeRig(friends: [friendA])
        XCTAssertEqual(rig.hub.requestFriend(code: rig.host.profile.friendCode), .isSelf)
        XCTAssertEqual(rig.hub.requestFriend(code: friendA), .alreadyFriend)
        guard case .invalid = rig.hub.requestFriend(input: "xyz") else { return XCTFail("不正なコードは弾く") }
        XCTAssertTrue(rig.host.profile.outgoingFriendRequests.isEmpty)
    }

    func testApprovingIncomingRequestMakesFriendsAndReplies() throws {
        let rig = makeRig()
        rig.net.last.receive(msg(from: friendA, #"{"k":"friendRequest","name":"Taro"}"#))
        XCTAssertEqual(rig.hub.incomingRequests, [FriendRequest(code: friendA, name: "Taro")])
        XCTAssertTrue(rig.hub.friends.isEmpty, "承認するまではフレンドではない")
        rig.hub.approve(rig.hub.incomingRequests[0])
        XCTAssertEqual(rig.hub.friends.map(\.code), [friendA])
        XCTAssertEqual(rig.hub.friends.first?.name, "Taro")
        XCTAssertTrue(rig.hub.incomingRequests.isEmpty)
        let reply = try XCTUnwrap(rig.net.last.sentJSON("send").last)
        XCTAssertEqual((reply["m"] as? [String: Any])?["k"] as? String, "friendAccept")
        XCTAssertEqual(reply["to"] as? String, friendA)
    }

    func testIgnoringRequestDropsItSilently() {
        let rig = makeRig()
        rig.net.last.receive(msg(from: friendA, #"{"k":"friendRequest","name":"Taro"}"#))
        rig.hub.ignore(rig.hub.incomingRequests[0])
        XCTAssertTrue(rig.hub.incomingRequests.isEmpty)
        XCTAssertTrue(rig.hub.friends.isEmpty)
        XCTAssertTrue(rig.net.last.sentJSON("send").isEmpty, "無視は相手に知らせない")
    }

    func testAcceptOnlyCountsWhenWeAsked() {
        let rig = makeRig()
        // 申請していない相手の承認は無視する（コードを知っているだけの相手が勝手にフレンドになれない）
        rig.net.last.receive(msg(from: stranger, #"{"k":"friendAccept","name":"Evil"}"#))
        XCTAssertTrue(rig.hub.friends.isEmpty)
        // 申請した相手の承認は成立する
        _ = rig.hub.requestFriend(code: friendA)
        rig.net.last.receive(msg(from: friendA, #"{"k":"friendAccept","name":"Taro"}"#))
        XCTAssertEqual(rig.hub.friends.map(\.code), [friendA])
        XCTAssertTrue(rig.host.profile.outgoingFriendRequests.isEmpty)
    }

    func testMutualRequestsBecomeFriendsImmediately() throws {
        let rig = makeRig()
        _ = rig.hub.requestFriend(code: friendA)
        rig.net.last.receive(msg(from: friendA, #"{"k":"friendRequest","name":"Taro"}"#))
        XCTAssertEqual(rig.hub.friends.map(\.code), [friendA])
        XCTAssertTrue(rig.hub.incomingRequests.isEmpty)
        let last = try XCTUnwrap(rig.net.last.sentJSON("send").last)
        XCTAssertEqual((last["m"] as? [String: Any])?["k"] as? String, "friendAccept")
    }

    func testRequestingSomeoneWhoAlreadyAskedAcceptsThem() {
        let rig = makeRig()
        rig.net.last.receive(msg(from: friendA, #"{"k":"friendRequest","name":"Taro"}"#))
        XCTAssertEqual(rig.hub.requestFriend(code: friendA), .accepted)
        XCTAssertEqual(rig.hub.friends.map(\.code), [friendA])
    }

    func testOutgoingRequestsAreResentWhenConnected() {
        let rig = makeRig(online: false)
        // 繋がる前に申請した（送れない）
        XCTAssertEqual(rig.hub.requestFriend(code: friendA), .sent)
        XCTAssertTrue(rig.net.last.sentJSON("send").isEmpty)
        rig.net.last.receive(#"{"t":"hello","code":"\#(rig.host.profile.friendCode)"}"#)
        XCTAssertEqual(rig.net.last.sentJSON("send").count, 1, "繋がったら申請を送り直す")
        XCTAssertEqual(rig.net.last.sentJSON("presence").count, 0, "フレンドがいなければ在席は聞かない")
    }

    func testRemoveFriend() {
        let rig = makeRig(friends: [friendA, friendB])
        rig.hub.removeFriend(code: friendA)
        XCTAssertEqual(rig.hub.friends.map(\.code), [friendB])
    }

    func testPresenceIsRequestedForFriendsAndStored() throws {
        let rig = makeRig(friends: [friendA, friendB])
        let asked = try XCTUnwrap(rig.net.last.sentJSON("presence").first)
        XCTAssertEqual(Set(asked["codes"] as? [String] ?? []), [friendA, friendB])
        rig.net.last.receive(#"{"t":"presence","online":["\#(friendB)"]}"#)
        XCTAssertTrue(rig.hub.isFriendOnline(friendB))
        XCTAssertFalse(rig.hub.isFriendOnline(friendA))
        // 切れたら全員オフライン扱い
        rig.net.last.fail()
        XCTAssertFalse(rig.hub.isFriendOnline(friendB))
    }

    // MARK: - ハブ: パーティの招待

    func testInviteFromNonFriendIsIgnored() {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: stranger, invitePayload()))
        XCTAssertNil(rig.hub.pendingInvite)
        XCTAssertTrue(rig.net.last.sentJSON("send").isEmpty, "フレンドでない相手には返事もしない")
    }

    func testInviteWithBadRoomCodeIsIgnored() {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: friendA, invitePayload(room: "BAD")))
        XCTAssertNil(rig.hub.pendingInvite)
    }

    func testInviteFromFriendShowsDialogAndAcceptJoins() throws {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        let invite = try XCTUnwrap(rig.hub.pendingInvite)
        XCTAssertEqual(invite.from, friendA)
        XCTAssertEqual(invite.room, roomCode)
        XCTAssertEqual(invite.name, "F-A", "名前は自分のフレンド一覧のもの（招待の名乗りではない）")
        rig.hub.respond(.accept)
        XCTAssertNil(rig.hub.pendingInvite)
        XCTAssertEqual(rig.joined.invites.map(\.room), [roomCode])
        let reply = try XCTUnwrap(rig.net.last.sentJSON("send").last)
        XCTAssertEqual(reply["to"] as? String, friendA)
        XCTAssertEqual((reply["m"] as? [String: Any])?["answer"] as? String, "accept")
        XCTAssertNil(reply["queue"], "招待への返事は預けない")
    }

    func testDeclineWithSuppressAutoDeclinesNextInvites() throws {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.hub.respond(.decline(suppress: true))
        XCTAssertNil(rig.hub.pendingInvite)
        XCTAssertTrue(rig.joined.invites.isEmpty)
        // 5 分間は出さずに断る
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        XCTAssertNil(rig.hub.pendingInvite)
        let answers = rig.net.last.sentJSON("send").compactMap { ($0["m"] as? [String: Any])?["answer"] as? String }
        XCTAssertEqual(answers, ["decline", "decline"])
        // 5 分後はまた届く
        var now = Date()
        rig.hub.now = { now }
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        XCTAssertNil(rig.hub.pendingInvite)
        now = now.addingTimeInterval(FriendHub.suppressSeconds + 1)
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        XCTAssertNotNil(rig.hub.pendingInvite)
    }

    func testDeclineWithoutSuppressDoesNotBlockNextInvite() {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.hub.respond(.decline(suppress: false))
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        XCTAssertNotNil(rig.hub.pendingInvite)
    }

    func testWaitRepliesAndJoinsAfterDelay() throws {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.hub.respond(.wait)
        XCTAssertNil(rig.hub.pendingInvite)
        XCTAssertTrue(rig.joined.invites.isEmpty, "待っている間は入らない")
        let reply = try XCTUnwrap(rig.net.last.sentJSON("send").last)
        XCTAssertEqual((reply["m"] as? [String: Any])?["answer"] as? String, "wait")
        XCTAssertEqual((reply["m"] as? [String: Any])?["wait"] as? Int, FriendHub.waitSeconds)
        XCTAssertTrue(rig.clock.delays.contains(TimeInterval(FriendHub.waitSeconds)))
        rig.clock.runAll()
        XCTAssertEqual(rig.joined.invites.map(\.room), [roomCode])
    }

    func testWaitedJoinIsCancelledWhenAMatchStarts() {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.hub.respond(.wait)
        rig.hub.declineAllAsBusy()
        rig.clock.runAll()
        XCTAssertTrue(rig.joined.invites.isEmpty)
    }

    func testBusyRepliesBusyAndShowsNothing() throws {
        let rig = makeRig(friends: [friendA])
        rig.hub.isBusy = { true }
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        XCTAssertNil(rig.hub.pendingInvite)
        let reply = try XCTUnwrap(rig.net.last.sentJSON("send").last)
        XCTAssertEqual((reply["m"] as? [String: Any])?["answer"] as? String, "busy")
    }

    func testDeclineAllAsBusyClearsDialogAndQueue() {
        let rig = makeRig(friends: [friendA, friendB])
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.net.last.receive(msg(from: friendB, invitePayload()))
        XCTAssertEqual(rig.hub.pendingInvite?.from, friendA)
        rig.hub.declineAllAsBusy()
        XCTAssertNil(rig.hub.pendingInvite)
        let answers = rig.net.last.sentJSON("send").compactMap { ($0["m"] as? [String: Any])?["answer"] as? String }
        XCTAssertEqual(answers, ["busy", "busy"])
    }

    func testSecondInviteWaitsBehindTheFirstAndStaleOnesAreDropped() {
        let rig = makeRig(friends: [friendA, friendB])
        var now = Date()
        rig.hub.now = { now }
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.net.last.receive(msg(from: friendB, invitePayload(room: "ABCDEF")))
        XCTAssertEqual(rig.hub.pendingInvite?.from, friendA)
        // 2 件目が古くなる前に 1 件目へ返事: 2 件目が出る
        rig.hub.respond(.decline(suppress: false))
        XCTAssertEqual(rig.hub.pendingInvite?.from, friendB)
        // 古い招待は捨てる
        rig.hub.respond(.decline(suppress: false))
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.net.last.receive(msg(from: friendB, invitePayload(room: "ABCDEF")))
        now = now.addingTimeInterval(FriendHub.inviteLifetime + 1)
        rig.hub.respond(.decline(suppress: false))
        XCTAssertNil(rig.hub.pendingInvite)
    }

    func testNewInviteFromSamePersonReplacesTheShownOne() {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(msg(from: friendA, invitePayload()))
        rig.net.last.receive(msg(from: friendA, invitePayload(room: "ABCDEF")))
        XCTAssertEqual(rig.hub.pendingInvite?.room, "ABCDEF")
        rig.hub.respond(.decline(suppress: false))
        XCTAssertNil(rig.hub.pendingInvite)
    }

    func testInviteSendsRoomCodeAndReportsResult() throws {
        let rig = makeRig(friends: [friendA])
        let friend = rig.hub.friends[0]
        rig.hub.invite(friend, roomCode: "bad", roomName: "Party")
        XCTAssertTrue(rig.net.last.sentJSON("send").isEmpty, "部屋コードが不正なら送らない")
        rig.hub.invite(friend, roomCode: roomCode, roomName: "Party")
        let sent = try XCTUnwrap(rig.net.last.sentJSON("send").first)
        let m = try XCTUnwrap(sent["m"] as? [String: Any])
        XCTAssertEqual(m["k"] as? String, "partyInvite")
        XCTAssertEqual(m["room"] as? String, roomCode)
        XCTAssertNil(sent["queue"], "招待は不在の相手に預けない")
        let id = try XCTUnwrap(sent["id"] as? Int)
        withJapanese { rig.net.last.receive(#"{"t":"ack","id":\#(id),"result":"offline"}"#) }
        XCTAssertEqual(rig.notices.texts.last, "F-A はオフラインです")
    }

    func testReplyToOurInviteIsShown() {
        let rig = makeRig(friends: [friendA])
        withJapanese {
            rig.net.last.receive(msg(from: friendA, #"{"k":"inviteReply","room":"\#(roomCode)","answer":"accept"}"#))
            XCTAssertEqual(rig.notices.texts.last, "F-A が参加します")
            rig.net.last.receive(msg(from: friendA, #"{"k":"inviteReply","room":"\#(roomCode)","answer":"wait","wait":30}"#))
            XCTAssertEqual(rig.notices.texts.last, "F-A は 30 秒後に参加します")
            rig.net.last.receive(msg(from: friendA, #"{"k":"inviteReply","room":"\#(roomCode)","answer":"decline"}"#))
            XCTAssertEqual(rig.notices.texts.last, "F-A は招待を断りました")
            rig.net.last.receive(msg(from: friendA, #"{"k":"inviteReply","room":"\#(roomCode)","answer":"busy"}"#))
            XCTAssertEqual(rig.notices.texts.last, "F-A は試合中です")
        }
        // フレンドでない相手の返事は無視する
        let count = rig.notices.texts.count
        rig.net.last.receive(msg(from: stranger, #"{"k":"inviteReply","answer":"accept"}"#))
        XCTAssertEqual(rig.notices.texts.count, count)
    }

    func testMessagesFromOurOwnCodeAreIgnored() {
        let rig = makeRig()
        rig.net.last.receive(msg(from: rig.host.profile.friendCode, #"{"k":"friendRequest","name":"Me"}"#))
        XCTAssertTrue(rig.hub.incomingRequests.isEmpty)
    }

    func testStopDisconnectsAndClearsPresence() {
        let rig = makeRig(friends: [friendA])
        rig.net.last.receive(#"{"t":"presence","online":["\#(friendA)"]}"#)
        rig.hub.stop()
        XCTAssertEqual(rig.hub.status, .offline)
        XCTAssertFalse(rig.hub.isFriendOnline(friendA))
        // 再開すると新しい接続を作る
        rig.hub.start()
        XCTAssertEqual(rig.net.sockets.count, 2)
    }

    // MARK: - パーティの席

    private func room(hostSeat: Int?, taken: [Int: String] = [:], phase: OnlineRoomPhase = .lobby) -> OnlineRoom {
        var room = OnlineRoom(name: "R", hostPeerID: "host")
        if let hostSeat { room.seats[hostSeat].peerID = "host" }
        for (i, id) in taken { room.seats[i].peerID = id }
        room.phase = phase
        return room
    }

    func testPartySeatIsFirstFreeSeatOnHostsTeam() {
        // ホストが Red の席に座っている: Red の最初の空席
        XCTAssertEqual(OnlineSession.partySeat(in: room(hostSeat: 7), for: "guest"), 5)
        // ホストが Blue（席 0）: Blue の次の空席
        XCTAssertEqual(OnlineSession.partySeat(in: room(hostSeat: 0), for: "guest"), 1)
        // Blue の途中が埋まっている
        XCTAssertEqual(OnlineSession.partySeat(in: room(hostSeat: 0, taken: [1: "a", 2: "b"]), for: "guest"), 3)
    }

    func testPartySeatDefaultsToBlueWhenHostIsNotSeated() {
        XCTAssertEqual(OnlineSession.partySeat(in: room(hostSeat: nil), for: "guest"), 0)
    }

    func testPartySeatFallsBackToOtherTeamWhenHostsTeamIsFull() {
        let full: [Int: String] = [1: "a", 2: "b", 3: "c", 4: "d"]
        XCTAssertEqual(OnlineSession.partySeat(in: room(hostSeat: 0, taken: full), for: "guest"), 5)
    }

    func testPartySeatIsNilWhenAlreadySeatedOrNotLobbyOrFull() {
        XCTAssertNil(OnlineSession.partySeat(in: room(hostSeat: 0, taken: [1: "guest"]), for: "guest"))
        XCTAssertNil(OnlineSession.partySeat(in: room(hostSeat: 0, phase: .playing), for: "guest"))
        var taken: [Int: String] = [:]
        for i in 1..<OnlineProtocol.seatCount { taken[i] = "p\(i)" }
        XCTAssertNil(OnlineSession.partySeat(in: room(hostSeat: 0, taken: taken), for: "guest"))
    }

    // MARK: - 保存データ

    func testOldProfileWithoutFriendKeysStillLoadsWithNewIdentity() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: PersistenceService.makeEncoder().encode(Profile())) as? [String: Any])
        for key in ["friendCode", "inboxKey", "friends", "outgoingFriendRequests"] { object[key] = nil }
        let merged = PersistenceService.mergingDefaults(into: object)
        let data = try JSONSerialization.data(withJSONObject: merged)
        let profile = try PersistenceService.makeDecoder().decode(Profile.self, from: data)
        XCTAssertTrue(FriendCode.isValid(profile.friendCode))
        XCTAssertTrue(FriendInboxKey.isValid(profile.inboxKey))
        XCTAssertTrue(profile.friends.isEmpty)
    }

    func testFriendsRoundTripThroughEncodeAndDecode() throws {
        var p = Profile()
        p.friends = [Friend(code: friendA, name: "Taro", addedAt: Date(timeIntervalSince1970: 100))]
        p.outgoingFriendRequests = [friendB]
        let data = try PersistenceService.makeEncoder().encode(p)
        let back = try PersistenceService.makeDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(back.friends, p.friends)
        XCTAssertEqual(back.outgoingFriendRequests, [friendB])
        XCTAssertEqual(back.friendCode, p.friendCode)
        // 友達の要素のキーが欠けた旧データも要素の既定値で補える
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["friends"] = [["code": friendA]]
        let merged = PersistenceService.mergingDefaults(into: object)
        let fixed = try PersistenceService.makeDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: merged))
        XCTAssertEqual(fixed.friends.map(\.code), [friendA])
    }

    func testSanitizeDropsBrokenFriendData() {
        var p = Profile()
        p.friendCode = "bad"
        p.inboxKey = "x"
        p.friends = [Friend(code: friendA, name: "A", addedAt: Date()), Friend(code: friendA, name: "dup", addedAt: Date()),
                     Friend(code: "bad", name: "B", addedAt: Date())]
        p.outgoingFriendRequests = [friendB, "bad"]
        PersistenceService.sanitize(&p)
        XCTAssertTrue(FriendCode.isValid(p.friendCode))
        XCTAssertNotEqual(p.friendCode, "bad")
        XCTAssertTrue(FriendInboxKey.isValid(p.inboxKey))
        XCTAssertEqual(p.friends.map(\.name), ["A"])
        XCTAssertEqual(p.outgoingFriendRequests, [friendB])
    }

    func testSanitizeRemovesOwnCodeFromFriends() {
        var p = Profile()
        p.friends = [Friend(code: p.friendCode, name: "self", addedAt: Date())]
        p.outgoingFriendRequests = [p.friendCode]
        PersistenceService.sanitize(&p)
        XCTAssertTrue(p.friends.isEmpty)
        XCTAssertTrue(p.outgoingFriendRequests.isEmpty)
    }

    // MARK: - 補助

    private func withJapanese<T>(_ body: () -> T) -> T {
        let saved = Loc.current
        Loc.current = .ja
        defer { Loc.current = saved }
        return body()
    }
}
