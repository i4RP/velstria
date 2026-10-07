import XCTest
@testable import VELSTRIA
import VelstriaCore

/// インターネット対戦の中継（OnlineRelay.swift）: 配線の形式・64 KiB の分割・部屋コード・close コードの文言と、
/// 中継の代役（InMemoryRelay。relay/ の Worker と同じ振る舞い）を通した OnlineSession の端から端まで
/// （コードで参加 → ロビー → ロックステップ → 200 KiB 超のスナップショット → 観戦 → ホストの切断・再接続 → no_room / room_taken）。
@MainActor
final class OnlineRelayTests: XCTestCase {
    private let blueMid = MatchFactory.onlineSeatIndex(team: .blue, position: .mid)
    private let redMid = MatchFactory.onlineSeatIndex(team: .red, position: .mid)

    // MARK: - 部品

    @MainActor
    private struct Rig {
        let relay: InMemoryRelay
        let clock: ManualRelayScheduler
        let host: OnlineSession
        var code: String { host.relayCode ?? "" }
    }

    /// 中継を開いたホスト。codes を渡すとその順にコードを作る（使われていれば次へ）。
    private func makeHost(relay given: InMemoryRelay? = nil, codes: [String]? = nil, fixed: String? = nil) -> Rig {
        let relay = given ?? InMemoryRelay()
        let clock = ManualRelayScheduler()
        let host = OnlineSession.host(peerID: "host", name: "Host", roomName: "Relay Room")
        var queue = codes ?? []
        let makeCode: (() -> String)? = codes == nil ? nil : {
            queue.isEmpty ? RelayRoomCode.generate() : queue.removeFirst()
        }
        host.startRelay(baseURL: InMemoryRelay.baseURL, code: fixed, makeSocket: relay.factory,
                        schedule: clock.scheduler, makeCode: makeCode)
        return Rig(relay: relay, clock: clock, host: host)
    }

    private func guestConnection(_ rig: Rig, code: String? = nil) -> RelayGuestConnection {
        RelayGuestConnection(code: code ?? rig.code, baseURL: InMemoryRelay.baseURL, makeSocket: rig.relay.factory)
    }

    private func join(_ rig: Rig, id: String, code: String? = nil, spectate: Bool = false) -> OnlineSession {
        OnlineSession.join(peerID: id, name: id.capitalized, connection: guestConnection(rig, code: code), wantsSpectate: spectate)
    }

    /// 中継の生の接続（中継の振る舞いを直接確かめる）。
    private func rawSocket(_ relay: InMemoryRelay, code: String, role: RelayRole, rv: Int = OnlineRelayConfig.relayVersion)
        -> (socket: RelaySocket, events: Events) {
        var url = OnlineRelayConfig.roomURL(base: InMemoryRelay.baseURL, code: code, role: role)
        if rv != OnlineRelayConfig.relayVersion {
            url = URL(string: url.absoluteString.replacingOccurrences(of: "rv=\(OnlineRelayConfig.relayVersion)", with: "rv=\(rv)"))!
        }
        let s = relay.factory(url)
        let e = Events()
        s.onOpen = { e.opened = true }
        s.onBinary = { e.binaries.append($0) }
        s.onText = { e.texts.append($0) }
        s.onClose = { code, reason in e.closed = (code, reason) }
        s.onFailure = { e.failure = $0 }
        s.connect()
        return (s, e)
    }

    private final class Events {
        var opened = false
        var binaries: [Data] = []
        var texts: [String] = []
        var closed: (code: Int, reason: String)?
        var failure: String?
    }

    private func withJapanese(_ body: () throws -> Void) rethrows {
        let saved = Loc.current
        Loc.current = .ja
        defer { Loc.current = saved }
        try body()
    }

    // MARK: - 配線の形式

    func testHeaderEncodeDecodeIsBigEndian() {
        let open = RelayWire.encode(.guestOpen(0x0102_0304))
        XCTAssertEqual([UInt8](open), [0x10, 0x01, 0x02, 0x03, 0x04])
        XCTAssertEqual(RelayWire.decodeServerMessage(open), .guestOpen(0x0102_0304))

        let payload = Data([0xAA, 0xBB, 0xCC])
        let data = RelayWire.encode(.guestData(7, payload))
        XCTAssertEqual([UInt8](data), [0x11, 0, 0, 0, 7, 0xAA, 0xBB, 0xCC])
        XCTAssertEqual(RelayWire.decodeServerMessage(data), .guestData(7, payload))
        XCTAssertEqual(RelayWire.decodeServerMessage(RelayWire.encode(.guestClose(UInt32.max))), .guestClose(UInt32.max))

        let send = RelayWire.encode(.send(42, payload))
        XCTAssertEqual([UInt8](send.prefix(5)), [0x21, 0, 0, 0, 42])
        XCTAssertEqual(RelayWire.decodeHostMessage(send), .send(42, payload))
        XCTAssertEqual([UInt8](RelayWire.encode(.kick(258))), [0x22, 0, 0, 1, 2])
        XCTAssertEqual(RelayWire.decodeHostMessage(RelayWire.encode(.kick(258))), .kick(258))

        // 短すぎる・未知の種類・向きの違う種類は読まない
        XCTAssertNil(RelayWire.decodeServerMessage(Data([0x10, 0, 0, 1])))
        XCTAssertNil(RelayWire.decodeServerMessage(Data()))
        XCTAssertNil(RelayWire.decodeServerMessage(Data([0x13, 0, 0, 0, 1])))
        XCTAssertNil(RelayWire.decodeServerMessage(send), "ホスト → 中継の種類は中継 → ホストとして読まない")
        XCTAssertNil(RelayWire.decodeHostMessage(open))
        // 切り出した Data（startIndex ≠ 0）でも読める
        let sliced = (Data([0xFF]) + data).dropFirst()
        XCTAssertEqual(RelayWire.decodeServerMessage(Data(sliced)), .guestData(7, payload))
        XCTAssertEqual(RelayWire.decodeServerMessage(sliced), .guestData(7, payload))
    }

    func testChunkingOver64KiBReassembles() throws {
        // 64 KiB を大きく超えるメッセージ（UTF-8 で約 360 KB）
        let big = OnlineMessage.reject(reason: String(repeating: "星", count: 120_000))
        let data = try OnlineFramer.encode(big)
        XCTAssertGreaterThan(data.count, 300 * 1024)
        let chunks = RelayWire.chunks(data, maxBytes: OnlineRelayConfig.chunkBytes)
        XCTAssertEqual(chunks.count, (data.count + OnlineRelayConfig.chunkBytes - 1) / OnlineRelayConfig.chunkBytes)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 64 * 1024 })
        XCTAssertEqual(chunks.reduce(Data(), +), data)
        var framer = OnlineFramer()
        var out: [OnlineMessage] = []
        for c in chunks { out += try framer.feed(c) }
        XCTAssertEqual(out, [big])
        XCTAssertEqual(framer.pendingBytes, 0)

        // 境界はどこでもよい（長さの途中・2 つのメッセージにまたがる）
        let two = try OnlineFramer.encode(.ping(1)) + OnlineFramer.encode(.pong(2))
        var f2 = OnlineFramer()
        var got: [OnlineMessage] = []
        for c in RelayWire.chunks(two, maxBytes: 3) { got += try f2.feed(c) }
        XCTAssertEqual(got, [.ping(1), .pong(2)])
        XCTAssertEqual(RelayWire.chunks(Data(), maxBytes: 10), [])
        // ホストの SEND はヘッダ込みで 64 KiB 以下
        XCTAssertEqual(RelayWire.chunks(data, maxBytes: OnlineRelayConfig.chunkBytes - RelayWire.headerBytes)
            .map { RelayWire.encode(.send(1, $0)).count }.max(), 64 * 1024)
    }

    // MARK: - 部屋コード

    func testCodeGenerationUsesOnlyUnambiguousCharacters() {
        XCTAssertEqual(RelayRoomCode.alphabet.count, 31)
        XCTAssertTrue(RelayRoomCode.ambiguous.isDisjoint(with: Set(RelayRoomCode.alphabet)))
        var seen = Set<Character>()
        var codes = Set<String>()
        for _ in 0..<2000 {
            let code = RelayRoomCode.generate()
            XCTAssertTrue(RelayRoomCode.isValid(code), code)
            XCTAssertTrue(InMemoryRelay.isValidCode(code), "中継の正規表現にも合う: \(code)")
            seen.formUnion(code)
            codes.insert(code)
        }
        XCTAssertEqual(seen, Set(RelayRoomCode.alphabet), "全ての文字が出る")
        XCTAssertGreaterThan(codes.count, 1990, "31^6 ≒ 8.9 億通り。2000 個でほぼ重ならない")
        // 乱数を渡せば決まった列になる（sim の乱数とは別。生成は SystemRandomNumberGenerator）
        var a = SplitMix64(seed: 9)
        var b = SplitMix64(seed: 9)
        XCTAssertEqual(RelayRoomCode.generate(using: &a), RelayRoomCode.generate(using: &b))
    }

    func testCodeNormalisationAndValidation() {
        // 小文字・空白・ハイフン・全角は正規化して通す
        XCTAssertEqual(try RelayRoomCode.parse("abcdef").get(), "ABCDEF")
        XCTAssertEqual(try RelayRoomCode.parse(" abc def ").get(), "ABCDEF")
        XCTAssertEqual(try RelayRoomCode.parse("ABC-DEF").get(), "ABCDEF")
        XCTAssertEqual(try RelayRoomCode.parse("ＡＢＣ　ｄｅｆ").get(), "ABCDEF", "全角・全角空白")
        XCTAssertEqual(try RelayRoomCode.parse("k7m-p2x").get(), "K7MP2X")
        // 招待の文面・リンクを貼り付けてもコードを取り出す
        XCTAssertEqual(try RelayRoomCode.parse("velstria://join?code=hj4k9z&spectate=1").get(), "HJ4K9Z")
        XCTAssertEqual(try RelayRoomCode.parse(OnlineJoinLink.shareText(code: "Q2W3E4", roomName: "部屋")).get(), "Q2W3E4")
        // 紛らわしい文字は読み替えずに弾く（I L O 0 1 はコードに無いので、正しい文字を推測できない）
        XCTAssertEqual(RelayRoomCode.parse("ABCDE0"), .failure(.ambiguous("0")))
        XCTAssertEqual(RelayRoomCode.parse("abcdeo"), .failure(.ambiguous("O")))
        XCTAssertEqual(RelayRoomCode.parse("1LIABC"), .failure(.ambiguous("1LI")))
        // 使えない文字・長さ
        XCTAssertEqual(RelayRoomCode.parse("ABC#EF"), .failure(.invalid("#")))
        XCTAssertEqual(RelayRoomCode.parse("ABCDE"), .failure(.tooShort(5)))
        XCTAssertEqual(RelayRoomCode.parse("ABCDEFG"), .failure(.tooLong(7)))
        XCTAssertEqual(RelayRoomCode.parse("  "), .failure(.empty))
        XCTAssertFalse(RelayRoomCode.isValid("abcdef"), "正規化前の小文字は不正")
        XCTAssertFalse(RelayRoomCode.isValid("ABCDE"))
        // 入力欄: 区切りを除いて大文字・6 文字まで（使えない文字は残してエラーを見せる）
        XCTAssertEqual(RelayRoomCode.cleaned("abc def gh"), "ABCDEF")
        XCTAssertEqual(RelayRoomCode.cleaned("ab0"), "AB0")
        XCTAssertEqual(RelayRoomCode.display("ABCDEF"), "ABC DEF")
        withJapanese {
            XCTAssertEqual(RelayRoomCode.InputError.tooShort(4).message, "部屋コードは 6 文字です（あと 2 文字）")
            XCTAssertTrue(RelayRoomCode.InputError.ambiguous("O").message.contains("I・L・O・0・1"))
        }
    }

    func testJoinLinkParsingAndBuilding() {
        let link = OnlineJoinLink(url: URL(string: "velstria://join?code=abc-def&spectate=1")!)
        XCTAssertEqual(link, OnlineJoinLink(code: "ABCDEF", spectate: true))
        XCTAssertEqual(OnlineJoinLink(url: URL(string: "VELSTRIA://join?code=ABCDEF")!)?.spectate, false)
        XCTAssertNil(OnlineJoinLink(url: URL(string: "velstria://join?code=ABCDE0")!), "不正なコード")
        XCTAssertNil(OnlineJoinLink(url: URL(string: "velstria://join")!), "コードが無い")
        XCTAssertNil(OnlineJoinLink(url: URL(string: "velstria://watch?code=ABCDEF")!), "知らない操作")
        XCTAssertNil(OnlineJoinLink(url: URL(string: "https://example.com/join?code=ABCDEF")!), "別のスキーム")
        XCTAssertNil(OnlineJoinLink(url: URL(fileURLWithPath: "/tmp/x.vreplay")), ".vreplay は扱わない（リプレイの取り込みへ）")
        XCTAssertEqual(OnlineJoinLink(code: "ABCDEF").url.absoluteString, "velstria://join?code=ABCDEF")
        XCTAssertEqual(OnlineJoinLink(url: OnlineJoinLink(code: "K7MP2X", spectate: true).url), OnlineJoinLink(code: "K7MP2X", spectate: true))
        let text = OnlineJoinLink.shareText(code: "K7MP2X", roomName: "Room")
        XCTAssertTrue(text.contains("K7M P2X"), "読みやすい表示")
        XCTAssertTrue(text.contains("velstria://join?code=K7MP2X"))
    }

    func testRoomURLAndBaseURL() {
        let base = URL(string: OnlineRelayConfig.defaultBaseURL)!
        XCTAssertEqual(OnlineRelayConfig.roomURL(base: base, code: "ABCDEF", role: .host).absoluteString,
                       "\(OnlineRelayConfig.defaultBaseURL)/v1/rooms/ABCDEF?role=host&rv=1")
        XCTAssertEqual(OnlineRelayConfig.roomURL(base: URL(string: "ws://127.0.0.1:8787/")!, code: "ABCDEF", role: .guest).absoluteString,
                       "ws://127.0.0.1:8787/v1/rooms/ABCDEF?role=guest&rv=1")
        XCTAssertEqual(OnlineRelayConfig.roomURL(base: URL(string: "wss://example.test/relay")!, code: "ABCDEF", role: .guest).absoluteString,
                       "wss://example.test/relay/v1/rooms/ABCDEF?role=guest&rv=1")
        XCTAssertNotNil(OnlineRelayConfig.validatedBaseURL(OnlineRelayConfig.defaultBaseURL))
        XCTAssertNotNil(OnlineRelayConfig.validatedBaseURL("ws://127.0.0.1:8787"))
        XCTAssertNil(OnlineRelayConfig.validatedBaseURL("https://example.test"), "WebSocket の URL だけ")
        XCTAssertNil(OnlineRelayConfig.validatedBaseURL("relay"))
        XCTAssertEqual(OnlineRelayConfig.baseURL.scheme, "wss", "既定は wss（-relayURL が無ければ）")
    }

    // MARK: - close コード

    func testCloseCodeMapping() {
        // 仕様の番号と理由の名前
        let expected: [(Int, String)] = [(4001, "host_left"), (4002, "closed_by_host"), (4004, "no_room"), (4008, "room_full"),
                                         (4009, "room_taken"), (4010, "relay_version")]
        for (code, name) in expected {
            XCTAssertEqual(RelayCloseCode(rawValue: code)?.reasonName, name)
        }
        XCTAssertEqual(RelayCloseCode.unsupportedData.rawValue, 1003)
        XCTAssertEqual(RelayCloseCode.messageTooBig.rawValue, 1009)
        withJapanese {
            XCTAssertEqual(RelayCloseCode.message(forCode: 4004), "部屋が見つかりません（コードを確かめてください）")
            XCTAssertTrue(RelayCloseCode.message(forCode: 4001).contains("ホスト"))
            XCTAssertTrue(RelayCloseCode.message(forCode: 4008).contains("満員"))
            XCTAssertTrue(RelayCloseCode.message(forCode: 4010).contains("更新"))
            XCTAssertTrue(RelayCloseCode.message(forCode: 4999).contains("4999"), "知らないコードは番号を出す")
            XCTAssertEqual(RelayCloseCode.connectFailureMessage(httpStatus: 400, detail: nil), "部屋コードが正しくありません")
            XCTAssertTrue(RelayCloseCode.connectFailureMessage(httpStatus: nil, detail: nil).contains("インターネット"))
        }
        // 利用者向けの文言はどれも別（どの理由で切れたか分かる）
        let messages = RelayCloseCode.allCases.filter { $0 != .goingAway }.map(\.message)
        XCTAssertEqual(Set(messages).count, messages.count)
        let saved = Loc.current
        Loc.current = .en
        XCTAssertEqual(RelayCloseCode.noRoom.message, "Room not found (check the code)")
        Loc.current = saved
    }

    // MARK: - 中継の代役が仕様どおりに振る舞う

    func testRelayDoubleFollowsServerRules() {
        let relay = InMemoryRelay()
        // 参加者: ホストがいなければ no_room
        let lonely = rawSocket(relay, code: "ABCDEF", role: .guest)
        XCTAssertTrue(lonely.events.opened, "受け入れてから閉じる")
        XCTAssertEqual(lonely.events.closed?.code, 4004)
        XCTAssertEqual(lonely.events.closed?.reason, "no_room")
        // 版数違いは relay_version
        let old = rawSocket(relay, code: "ABCDEF", role: .host, rv: 0)
        XCTAssertEqual(old.events.closed?.code, 4010)
        // 不正なコードは繋がらない（400）
        let bad = relay.factory(URL(string: "wss://relay.test/v1/rooms/ABCDE0?role=host&rv=1")!)
        var failure: String?
        bad.onFailure = { failure = $0 }
        // 文言は作られた時の表示言語で決まる（CI は英語）ので、接続も日本語の間に行う
        withJapanese {
            bad.connect()
            XCTAssertEqual(failure, "部屋コードが正しくありません")
        }

        // ホスト: 2 台目は room_taken
        let host = rawSocket(relay, code: "ABCDEF", role: .host)
        XCTAssertTrue(host.events.opened)
        XCTAssertNil(host.events.closed)
        let second = rawSocket(relay, code: "ABCDEF", role: .host)
        XCTAssertEqual(second.events.closed?.code, 4009)
        XCTAssertNil(host.events.closed, "先のホストはそのまま")

        // ping → pong（テキストはそれ以外無視）
        host.socket.send(text: "ping")
        host.socket.send(text: "hello")
        XCTAssertEqual(host.events.texts, ["pong"])

        // 参加者: GUEST_OPEN / GUEST_DATA / SEND / GUEST_CLOSE、ID は増えるだけで再利用しない
        let g1 = rawSocket(relay, code: "ABCDEF", role: .guest)
        XCTAssertEqual(host.events.binaries.last.flatMap(RelayWire.decodeServerMessage), .guestOpen(1))
        g1.socket.send(binary: Data([1, 2, 3]))
        XCTAssertEqual(host.events.binaries.last.flatMap(RelayWire.decodeServerMessage), .guestData(1, Data([1, 2, 3])))
        host.socket.send(binary: RelayWire.encode(.send(1, Data([9]))))
        XCTAssertEqual(g1.events.binaries, [Data([9])])
        g1.socket.close(code: 1000, reason: "bye")
        XCTAssertEqual(host.events.binaries.last.flatMap(RelayWire.decodeServerMessage), .guestClose(1))
        let g2 = rawSocket(relay, code: "ABCDEF", role: .guest)
        XCTAssertEqual(host.events.binaries.last.flatMap(RelayWire.decodeServerMessage), .guestOpen(2), "ID は再利用しない")
        // KICK → closed_by_host
        host.socket.send(binary: RelayWire.encode(.kick(2)))
        XCTAssertEqual(g2.events.closed?.code, 4002)

        // 32 人まで。33 人目は room_full
        var guests: [(socket: RelaySocket, events: Events)] = []
        for _ in 0..<OnlineRelayConfig.maxGuests { guests.append(rawSocket(relay, code: "ABCDEF", role: .guest)) }
        XCTAssertTrue(guests.allSatisfy { $0.events.closed == nil })
        XCTAssertEqual(relay.guestCount("ABCDEF"), 32)
        let full = rawSocket(relay, code: "ABCDEF", role: .guest)
        XCTAssertEqual(full.events.closed?.code, 4008)

        // 256 KiB を超えるメッセージは 1009（その接続だけ）
        guests[0].socket.send(binary: Data(count: OnlineRelayConfig.serverMaxMessageBytes + 1))
        XCTAssertEqual(guests[0].events.closed?.code, 1009)
        XCTAssertNil(guests[1].events.closed)

        // ホストの不正な形式は 1003 → ホストがいなくなるので全参加者は host_left
        host.socket.send(binary: Data([0x7F, 0, 0, 0, 1]))
        XCTAssertEqual(host.events.closed?.code, 1003)
        XCTAssertTrue(guests.dropFirst().allSatisfy { $0.events.closed?.code == 4001 })
        XCTAssertFalse(relay.hasHost("ABCDEF"))
    }

    // MARK: - OnlineSession を中継で通す

    func testLobbyJoinByCode() {
        let rig = makeHost()
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertTrue(RelayRoomCode.isValid(rig.code))
        XCTAssertTrue(rig.relay.hasHost(rig.code))

        let guest = join(rig, id: "guest")
        XCTAssertEqual(guest.status, .lobby)
        XCTAssertEqual(guest.joinedRelayCode, rig.code)
        XCTAssertEqual(guest.room.name, "Relay Room")
        XCTAssertEqual(rig.host.room.peers.map(\.id), ["host", "guest"])
        XCTAssertEqual(rig.host.relayGuestCount, 1)

        guest.takeSeat(redMid)
        XCTAssertEqual(rig.host.room.seatIndex(of: "guest"), redMid)
        XCTAssertEqual(guest.room, rig.host.room, "部屋はホストの正本が配られる")

        // LAN（ここではループバック）の参加者と同じ部屋に入る（どちらも accept に入る）
        let (a, b) = LoopbackConnection.pair()
        rig.host.accept(a)
        let lan = OnlineSession.join(peerID: "lan", name: "Lan", connection: b)
        XCTAssertEqual(lan.status, .lobby)
        XCTAssertEqual(Set(guest.room.peers.map(\.id)), ["host", "guest", "lan"])

        // 生存確認の ping/pong も中継の上で往復する
        guest.ping()
        rig.host.ping()
        XCTAssertNotNil(guest.rtt)

        // 参加者が退出すると、ホストに GUEST_CLOSE が届いて部屋から外れる
        guest.leave()
        XCTAssertFalse(rig.host.room.peers.contains { $0.id == "guest" })
    }

    func testGuestKeepalivePongAndHostSilenceReconnects() {
        let rig = makeHost()
        let conn = guestConnection(rig)
        let guest = OnlineSession.join(peerID: "guest", name: "Guest", connection: conn)
        XCTAssertEqual(guest.status, .lobby)
        conn.sendKeepalive()
        let guestSocket = rig.relay.sockets.last { $0.url.query?.contains("role=guest") == true }
        XCTAssertEqual(guestSocket?.receivedTexts, ["pong"], "中継の自動応答")

        // ホスト: 中継から長く何も届かなければ繋ぎ直す（コードは保つ）
        var now: TimeInterval = 100
        let link = RelayHostLink(baseURL: InMemoryRelay.baseURL, code: nil, makeSocket: rig.relay.factory, schedule: rig.clock.scheduler)
        link.uptime = { now }
        link.makeCode = { "HKX3MZ" }
        link.start()
        XCTAssertEqual(link.status, .ready)
        now += 10
        link.keepaliveTick()   // ping → pong で最後の受信が更新される
        XCTAssertEqual(link.status, .ready)
        now += OnlineRelayConfig.silenceTimeout + 1
        rig.relay.holdsDelivery = true   // pong が届かない
        link.keepaliveTick()
        guard case .reconnecting = link.status else { return XCTFail("無応答で繋ぎ直す: \(link.status)") }
        rig.relay.holdsDelivery = false
        rig.clock.runAll()
        XCTAssertEqual(link.status, .ready)
        XCTAssertEqual(link.code, "HKX3MZ")
        link.stop()
    }

    func testLargeMessagesAreChunkedBothWays() throws {
        let rig = makeHost()
        let conn = guestConnection(rig)
        var received: [OnlineMessage] = []
        conn.onMessage = { received.append($0) }
        conn.start()
        XCTAssertEqual(conn.state, .ready)
        // ホストの仮想接続（中継の向こうの参加者）は accept に入っている。名乗りをせず、生の接続同士で送り合う
        let endpointCount = rig.host.relayGuestCount
        XCTAssertEqual(endpointCount, 1)

        // 参加者 → ホスト: 300 KB 超の名乗り（壊れていないことを部屋の名前で確かめる）
        let longName = String(repeating: "名", count: 100_000)
        conn.send(.hello(OnlineHello(peerID: "big", name: longName)))
        XCTAssertLessThanOrEqual(rig.relay.largestGuestMessage, 64 * 1024)
        XCTAssertEqual(rig.host.room.peer("big")?.name, longName, "64 KiB に分けても組み直せる")
        guard case .welcome(let room)? = received.first else { return XCTFail("\(received.count)") }
        XCTAssertEqual(room.peer("big")?.name, longName)
        XCTAssertLessThanOrEqual(rig.relay.largestHostMessage, 64 * 1024, "ホストの SEND もヘッダ込みで 64 KiB 以下")
        XCTAssertGreaterThan(rig.relay.hostBinaryCount, 5)
    }

    // MARK: 対戦

    /// 両者が着席・ピック・準備完了し、ホストが開始した状態。
    private func startedMatch(_ rig: Rig, guest: OnlineSession, seed: UInt64 = 42) -> MatchConfig {
        rig.host.takeSeat(blueMid)
        guest.takeSeat(redMid)
        rig.host.setLoadout(OnlineLoadout(heroID: "H001"))
        guest.setLoadout(OnlineLoadout(heroID: "H002"))
        rig.host.setReady(true)
        guest.setReady(true)
        var hostStart: MatchConfig?
        var guestStart: (MatchConfig, Int?)?
        rig.host.onMatchStart = { c, _ in hostStart = c }
        guest.onMatchStart = { guestStart = ($0, $1) }
        XCTAssertTrue(rig.host.startMatch(master: .shared, seed: seed))
        XCTAssertEqual(guestStart?.1, redMid)
        XCTAssertEqual(hostStart, guestStart?.0)
        return hostStart!
    }

    private func run(_ host: BattleController, _ client: BattleController, frames: Int) {
        for _ in 0..<frames {
            host.frame(dt: Balance.dt)
            client.frame(dt: Balance.dt)
        }
    }

    private func catchUp(_ client: BattleController, to host: BattleController) {
        var n = 0
        while client.state.tick < host.state.tick, n < 200 {
            client.frame(dt: Balance.dt)
            n += 1
        }
        XCTAssertEqual(client.state.tick, host.state.tick)
    }

    func testLockstepMatchOverRelayKeepsHashesEqual() {
        let rig = makeHost()
        let guest = join(rig, id: "guest")
        let config = startedMatch(rig, guest: guest)
        let host = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: rig.host)
        let client = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: guest)
        rig.host.attach(controller: host)
        XCTAssertFalse(rig.host.canBegin, "参加者の読み込みを待つ")
        guest.attach(controller: client)
        XCTAssertTrue(rig.host.canBegin)

        let clientHero = client.humanHeroID!
        let start = host.state.unit(clientHero)!.pos
        client.send(.move(direction: Vec2(1, 0)))
        run(host, client, frames: 150)
        XCTAssertNotEqual(host.state.unit(clientHero)!.pos, start, "中継越しの入力がホストで適用された")
        let hostHero = host.humanHeroID!
        let hostStart = host.state.unit(hostHero)!.pos
        host.send(.move(direction: Vec2(0, 1)))
        run(host, client, frames: 90)
        catchUp(client, to: host)
        XCTAssertNotEqual(client.state.unit(hostHero)!.pos, hostStart)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(rig.host.resyncCount, 0, "ハッシュ報告はすべて一致")
        XCTAssertEqual(guest.resyncCount, 0)
        XCTAssertEqual(host.recorder?.frames, client.recorder?.frames)
        XCTAssertLessThanOrEqual(rig.relay.largestHostMessage, 64 * 1024)
    }

    func testSnapshotOver200KiBResyncsThroughRelay() throws {
        let rig = makeHost()
        let guest = join(rig, id: "guest")
        let config = startedMatch(rig, guest: guest)
        let host = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: rig.host)
        let client = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: guest)
        rig.host.attach(controller: host)
        guest.attach(controller: client)
        run(host, client, frames: 600)
        catchUp(client, to: host)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())

        // 終盤の戦場（ユニット 130 体前後。スナップショットは 200 KiB を超える。序盤の 20 秒では約 120 KB）の大きさにする:
        // ホストの状態にミニオン・中立モンスターの写しを足す（テストだけの状態の操作。規則は変えない）。
        // 参加者の状態とはずれるので、次のハッシュ報告でホストがその状態を丸ごと送る
        var big = host.state
        let extras = big.units.filter { $0.kind == .minion || $0.kind == .monster }
        XCTAssertFalse(extras.isEmpty)
        var rounds = 0
        while try OnlineFramer.encode(.snapshot(big)).count <= 210 * 1024, rounds < 10 {
            for u in extras { big.addUnit(u) }
            rounds += 1
        }
        big.events = host.state.events
        let size = try OnlineFramer.encode(.snapshot(big)).count
        XCTAssertGreaterThan(size, 200 * 1024, "スナップショット \(size) バイト")
        XCTAssertLessThan(size, 2 * OnlineRelayConfig.serverMaxMessageBytes)
        host.restore(big)

        let before = rig.relay.hostBinaryCount
        run(host, client, frames: 90)
        XCTAssertEqual(rig.host.resyncCount, 1)
        XCTAssertEqual(guest.resyncCount, 1)
        catchUp(client, to: host)
        XCTAssertEqual(client.state.units.count, host.state.units.count)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
        // 中継の上限（256 KiB）に近い状態でも、64 KiB 以下に分けて送られた
        XCTAssertLessThanOrEqual(rig.relay.largestHostMessage, 64 * 1024)
        XCTAssertGreaterThanOrEqual(rig.relay.hostBinaryCount - before, size / (64 * 1024) + 1, "分割して送った")
        XCTAssertFalse(rig.relay.closeLog.contains(RelayCloseCode.messageTooBig.rawValue))

        // 以後は再同期が増えない
        run(host, client, frames: 90)
        catchUp(client, to: host)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(rig.host.resyncCount, 1)
    }

    func testSpectatorJoinsByCodeAndWatchesDelayed() {
        let delay = 60
        let rig = makeHost()
        rig.host.encodesSpectatorSnapshotsInBackground = false
        rig.host.spectatorKeyframeInterval = 60
        rig.host.setSpectatorDelay(ticks: delay)
        rig.host.takeSeat(blueMid)
        rig.host.setLoadout(OnlineLoadout(heroID: "H001"))
        rig.host.setReady(true)

        // 観戦席でコードから入る → 試合開始で観戦の案内
        let watcher = join(rig, id: "watcher", spectate: true)
        XCTAssertEqual(watcher.localRole, .spectator)
        XCTAssertTrue(watcher.joinedAsSpectator)
        var spectateConfig: MatchConfig?
        watcher.onSpectateStart = { spectateConfig = $0 }
        XCTAssertTrue(rig.host.startMatch(master: .shared, seed: 77))
        XCTAssertEqual(spectateConfig, rig.host.room.config)
        let hc = BattleController(launch: BattleLaunch(config: rig.host.room.config!, onlineSeat: blueMid), online: rig.host)
        rig.host.attach(controller: hc)
        let wc = BattleController(launch: BattleLaunch(config: watcher.room.config!, onlineSpectator: true), online: watcher)
        watcher.attach(controller: wc)
        XCTAssertEqual(rig.host.spectatorStreamCount, 1)

        var hashes: [Int: UInt64] = [:]
        // 途中から観戦席でもう 1 人入る（遅延済みのキーフレームが中継越しに届く）
        var late: OnlineSession?
        var lateController: BattleController?
        for frame in 0..<420 {
            hc.frame(dt: Balance.dt)
            hashes[hc.state.tick] = hc.state.stateHash()
            rig.host.pumpSpectators()
            wc.frame(dt: Balance.dt)
            lateController?.frame(dt: Balance.dt)
            XCTAssertLessThanOrEqual(wc.state.tick, max(0, hc.state.tick - delay), "観戦者は生の状態に追いつかない")
            if frame == 200 {
                let l = join(rig, id: "late", spectate: true)
                late = l
                XCTAssertTrue(l.isWatchingMatch, "試合中の観戦席には案内がすぐ届く")
                let c = BattleController(launch: BattleLaunch(config: l.room.config!, onlineSpectator: true), online: l)
                l.attach(controller: c)
                lateController = c
            }
        }
        XCTAssertGreaterThan(wc.state.tick, 300)
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick], "遅れた tick でホストと同じ状態")
        XCTAssertNotNil(late?.lastSnapshotTick, "途中参加はキーフレームから")
        XCTAssertNotNil(lateController)
        if let lc = lateController {
            XCTAssertGreaterThan(lc.state.tick, 250)
            XCTAssertEqual(lc.state.stateHash(), hashes[lc.state.tick])
        }
        XCTAssertEqual(rig.host.resyncCount, 0)
        XCTAssertEqual(rig.host.room.watchingCount, 2)
    }

    // MARK: 切断・再接続

    func testHostDropClosesGuestsWithHostLeftAndReconnectKeepsCode() {
        let rig = makeHost()
        let code = rig.code
        let guest = join(rig, id: "guest")
        let config = startedMatch(rig, guest: guest)
        let host = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: rig.host)
        let client = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: guest)
        rig.host.attach(controller: host)
        guest.attach(controller: client)
        run(host, client, frames: 30)
        let clientHero = client.humanHeroID!

        // ホストの回線が切れる → 中継は参加者を host_left で閉じる。ホストは参加者を AI に引き継ぎ、同じコードで繋ぎ直す
        rig.relay.dropHost(code)
        XCTAssertEqual(guest.status, .disconnected(RelayCloseCode.hostLeft.message))
        XCTAssertEqual(guest.joinedRelayCode, code, "同じコードで入り直せる")
        guard case .reconnecting? = rig.host.relayStatus else { return XCTFail("再接続中: \(String(describing: rig.host.relayStatus))") }
        host.frame(dt: Balance.dt)
        XCTAssertEqual(host.state.unit(clientHero)?.hero?.controller, .bot)
        XCTAssertEqual(rig.host.room.seatIndex(of: "guest"), redMid, "座席は保つ")
        XCTAssertEqual(rig.clock.delays.last, OnlineRelayConfig.reconnectBaseDelay, "初回の待ちはバックオフの初期値")

        rig.clock.runAll()
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertEqual(rig.host.relayCode, code, "部屋コードは変わらない")
        for _ in 0..<30 { host.frame(dt: Balance.dt) }

        // 同じ peerID・同じコードで入り直す → 試合の構成 → 読み込み → スナップショット → 操作権が戻る
        let guest2 = join(rig, id: "guest", code: code)
        XCTAssertEqual(guest2.status, .loading, "試合中の再接続は読み込みへ")
        let client2 = BattleController(launch: BattleLaunch(config: guest2.room.config!, onlineSeat: redMid), online: guest2)
        guest2.attach(controller: client2)
        XCTAssertEqual(guest2.resyncCount, 1, "スナップショットが届く")
        run(host, client2, frames: 60)
        catchUp(client2, to: host)
        XCTAssertEqual(host.state.unit(clientHero)?.hero?.controller, .human)
        XCTAssertEqual(client2.state.stateHash(), host.state.stateHash())
    }

    func testStrandedHostReconnectWaitsForSameCodeThenRegenerates() {
        // 入れ替え（hk）のない古い中継: 古い接続が片付くまで room_taken
        let relay = InMemoryRelay()
        relay.supportsTakeover = false
        let rig = makeHost(relay: relay, codes: ["K7MP2X", "Q2W3E4"])
        XCTAssertEqual(rig.code, "K7MP2X")
        // 中継が古いホストの接続にまだ気づいていない（半開き）: 再接続は room_taken
        rig.relay.strandHost("K7MP2X")
        rig.clock.runAll()
        guard case .reconnecting? = rig.host.relayStatus else { return XCTFail("\(String(describing: rig.host.relayStatus))") }
        XCTAssertEqual(rig.host.relayCode, "K7MP2X", "確保していたコードは保って待つ")
        // 中継が古い接続を片付けたら、同じコードで戻れる
        rig.relay.reapStrandedHost("K7MP2X")
        rig.clock.runAll()
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertEqual(rig.host.relayCode, "K7MP2X")

        // いつまでも片付かなければ、同じコードで数回待った後にコードを作り直す
        rig.relay.strandHost("K7MP2X")
        for _ in 0...OnlineRelayConfig.roomTakenSameCodeRetries { rig.clock.runAll() }
        XCTAssertEqual(rig.host.relayCode, "Q2W3E4")
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertTrue(rig.host.events.contains { $0.contains("Q2W") }, "コードが変わったことを知らせる")
    }

    func testStrandedHostReconnectTakesOverWithResumeKeyAndKeepsTheCode() {
        let rig = makeHost(codes: ["K7MP2X"])
        let guest = join(rig, id: "guest")
        XCTAssertTrue(guest.isConnected)
        // ホストの回線が黙って死に、中継はまだ前の接続を生かしている（半開き）。繋ぎ直すと、同じ鍵で入れ替わる
        rig.relay.strandHost("K7MP2X")
        rig.clock.runAll()
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertEqual(rig.host.relayCode, "K7MP2X", "コードは作り直さない")
        XCTAssertTrue(rig.relay.closeLog.contains(RelayCloseCode.hostReplaced.rawValue), "前の接続は 4011 で閉じる")
        XCTAssertFalse(rig.relay.closeLog.contains(RelayCloseCode.roomTaken.rawValue), "room_taken を待たない")
        XCTAssertEqual(guest.status, .disconnected(RelayCloseCode.hostLeft.message), "前の接続の参加者は host_left")
        XCTAssertFalse(rig.host.events.contains { $0.contains("Q2W") })
        // 参加者は同じコードで入り直せる
        let again = join(rig, id: "guest", code: "K7MP2X")
        XCTAssertTrue(again.isConnected)
        XCTAssertEqual(rig.relay.guestCount("K7MP2X"), 1)
    }

    func testResumeKeyIsStableAcrossReconnectsAndOnlyOnTheHostURL() {
        let rig = makeHost(codes: ["K7MP2X"])
        func hostURLs() -> [URL] { rig.relay.sockets.map(\.url).filter { $0.absoluteString.contains("role=host") } }
        XCTAssertEqual(hostURLs().count, 1)
        rig.relay.dropHost("K7MP2X")
        rig.clock.runAll()
        let urls = hostURLs()
        XCTAssertEqual(urls.count, 2)
        let keys = urls.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "hk" }?.value }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1], "同じ部屋の間は同じ鍵")
        XCTAssertTrue(InMemoryRelay.isValidResumeKey(keys[0]), "中継の形式（16〜64 文字の英数・_・-）: \(keys[0])")
        XCTAssertEqual(keys[0].count, 32)
        // 参加者の URL に鍵は付かない
        let guest = join(rig, id: "guest")
        _ = guest
        let guestURLs = rig.relay.sockets.map(\.url).filter { $0.absoluteString.contains("role=guest") }
        XCTAssertFalse(guestURLs.isEmpty)
        XCTAssertTrue(guestURLs.allSatisfy { !$0.absoluteString.contains("hk=") })
        // 別の部屋・別のリンクは別の鍵
        let other = makeHost(codes: ["Q2W3E4"])
        let otherKey = other.relay.sockets.first.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "hk" }?.value }
        XCTAssertNotEqual(otherKey, keys[0])
    }

    func testHostRoomURLCarriesResumeKeyOnlyForHost() {
        let base = InMemoryRelay.baseURL
        XCTAssertEqual(OnlineRelayConfig.roomURL(base: base, code: "ABCDEF", role: .host, resumeKey: "k1k1k1k1k1k1k1k1").absoluteString,
                       "wss://relay.test/v1/rooms/ABCDEF?role=host&rv=1&hk=k1k1k1k1k1k1k1k1")
        XCTAssertEqual(OnlineRelayConfig.roomURL(base: base, code: "ABCDEF", role: .guest, resumeKey: "k1k1k1k1k1k1k1k1").absoluteString,
                       "wss://relay.test/v1/rooms/ABCDEF?role=guest&rv=1")
    }

    func testHostReplacedCloseCodeHasNameAndMessage() {
        XCTAssertEqual(RelayCloseCode(rawValue: 4011), .hostReplaced)
        XCTAssertEqual(RelayCloseCode.hostReplaced.reasonName, "host_replaced")
        XCTAssertFalse(RelayCloseCode.hostReplaced.message.isEmpty)
    }

    func testRelayGuestMessageLimitStopsAnOversizedLengthBeforeHello() throws {
        // 名乗る前の参加者が 32 MiB の長さだけ宣言して滴らせても、ホストは 1 MiB 超を持たない
        var framer = OnlineFramer(maxMessageBytes: OnlineRelayConfig.guestToHostMaxMessageBytes)
        var length = UInt32(OnlineRelayConfig.guestToHostMaxMessageBytes + 1).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        XCTAssertThrowsError(try framer.feed(header)) { error in
            XCTAssertEqual(error as? OnlineFramer.FramingError, .oversized(OnlineRelayConfig.guestToHostMaxMessageBytes + 1))
        }
        // 通常のメッセージ（名乗り・入力）は通る
        var ok = OnlineFramer(maxMessageBytes: OnlineRelayConfig.guestToHostMaxMessageBytes)
        XCTAssertEqual(try ok.feed(OnlineFramer.encode(.ping(5))), [.ping(5)])
    }

    func testRelayGuestThatNeverSaysHelloIsDroppedAfterHandshakeTimeout() {
        let relay = InMemoryRelay()
        let clock = ManualRelayScheduler()
        var now: TimeInterval = 1000
        let host = OnlineSession.host(peerID: "host", name: "Host", roomName: "Relay Room")
        host.uptime = { now }
        host.startRelay(baseURL: InMemoryRelay.baseURL, code: "K7MP2X", makeSocket: relay.factory, schedule: clock.scheduler)
        // 名乗らない生の参加者
        let silent = rawSocket(relay, code: "K7MP2X", role: .guest)
        XCTAssertTrue(silent.events.opened)
        XCTAssertEqual(host.relayGuestCount, 1)
        host.ping()
        XCTAssertEqual(host.relayGuestCount, 1, "猶予の間は保つ")
        now += OnlineProtocol.handshakeTimeout + 1
        host.ping()
        XCTAssertEqual(host.relayGuestCount, 0, "名乗らないまま猶予を過ぎたら切る")
        XCTAssertEqual(relay.guestCount("K7MP2X"), 0, "中継からも外れる（KICK）")
        // 名乗った参加者は猶予の影響を受けない
        let real = OnlineSession.join(peerID: "guest", name: "Guest",
                                      connection: RelayGuestConnection(code: "K7MP2X", baseURL: InMemoryRelay.baseURL, makeSocket: relay.factory))
        XCTAssertTrue(real.isConnected)
        now += OnlineProtocol.handshakeTimeout + 1
        host.ping()
        XCTAssertEqual(host.relayGuestCount, 1)
    }

    func testRetryFromFailedShowsConnectingAgain() {
        let relay = InMemoryRelay()
        relay.isReachable = false
        let rig = makeHost(relay: relay, codes: ["K7MP2X"])
        for _ in 0..<(OnlineRelayConfig.maxReconnectAttempts + 2) { rig.clock.runAll() }
        guard case .failed? = rig.host.relayStatus else { return XCTFail("失敗: \(String(describing: rig.host.relayStatus))") }
        relay.isReachable = true
        relay.holdsDelivery = true
        rig.host.retryRelay()
        XCTAssertEqual(rig.host.relayStatus, .connecting, "再試行を押したら、結果を待つ間は接続中と見せる")
        relay.holdsDelivery = false
        rig.clock.runAll()
        XCTAssertEqual(rig.host.relayStatus, .ready)
    }

    func testNoRoomShowsMessage() {
        let relay = InMemoryRelay()
        let conn = RelayGuestConnection(code: "ZZZZZZ", baseURL: InMemoryRelay.baseURL, makeSocket: relay.factory)
        let guest = OnlineSession.join(peerID: "guest", name: "Guest", connection: conn)
        XCTAssertEqual(guest.status, .disconnected(RelayCloseCode.noRoom.message))
        withJapanese { XCTAssertEqual(RelayCloseCode.noRoom.message, "部屋が見つかりません（コードを確かめてください）") }
        XCTAssertEqual(relay.closeLog, [4004])
        // 正規化前のコード（小文字）は中継へ行く前に断る
        let bad = RelayGuestConnection(code: "abcdef", baseURL: InMemoryRelay.baseURL, makeSocket: relay.factory)
        let g2 = OnlineSession.join(peerID: "g2", name: "G2", connection: bad)
        guard case .disconnected = g2.status else { return XCTFail("\(g2.status)") }
        XCTAssertEqual(relay.sockets.count, 1)
    }

    func testRoomTakenRegeneratesUpToThreeTimes() {
        let relay = InMemoryRelay()
        // 別のホストが使っているコード
        let holders = ["AAAAAA", "BBBBBB", "CCCCCC", "DDDDDD"].map { rawSocket(relay, code: $0, role: .host) }
        XCTAssertTrue(holders.allSatisfy { $0.events.closed == nil })

        let rig = makeHost(relay: relay, codes: ["AAAAAA", "BBBBBB", "EEEEEE"])
        XCTAssertEqual(rig.code, "EEEEEE", "使われていたコードは作り直す")
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertEqual(relay.closeLog.filter { $0 == 4009 }.count, 2)
        let guest = join(rig, id: "guest")
        XCTAssertEqual(guest.status, .lobby)

        // 作り直しても全部使われていたら諦める（再試行で繋ぎ直す）
        let rig2 = makeHost(relay: relay, codes: ["AAAAAA", "BBBBBB", "CCCCCC", "DDDDDD", "FFFFFF"])
        guard case .failed? = rig2.host.relayStatus else { return XCTFail("\(String(describing: rig2.host.relayStatus))") }
        XCTAssertEqual(rig2.code, "DDDDDD", "最初 + 作り直し 3 回")
        rig2.host.retryRelay()
        XCTAssertEqual(rig2.host.relayStatus, .ready)
        XCTAssertEqual(rig2.code, "FFFFFF")
    }

    func testFixedCodeIsKeptWhenTaken() {
        let relay = InMemoryRelay()
        let holder = rawSocket(relay, code: "HJ4K9Z", role: .host)
        let rig = makeHost(relay: relay, fixed: "HJ4K9Z")
        XCTAssertEqual(rig.code, "HJ4K9Z")
        guard case .reconnecting? = rig.host.relayStatus else { return XCTFail("\(String(describing: rig.host.relayStatus))") }
        rig.clock.runAll()
        XCTAssertEqual(rig.code, "HJ4K9Z", "決めたコードは作り直さない")
        holder.socket.close(code: 1000, reason: "bye")
        rig.clock.runAll()
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertEqual(rig.code, "HJ4K9Z")
    }

    func testUnreachableRelayBacksOffThenFails() {
        let relay = InMemoryRelay()
        relay.isReachable = false
        let rig = makeHost(relay: relay)
        let code = rig.code
        for _ in 0..<OnlineRelayConfig.maxReconnectAttempts { rig.clock.runAll() }
        guard case .failed? = rig.host.relayStatus else { return XCTFail("\(String(describing: rig.host.relayStatus))") }
        XCTAssertEqual(rig.clock.delays.prefix(6), [1, 2, 4, 8, 16, 30], "指数バックオフ（上限 30 秒）")
        // LAN の部屋はそのまま使える
        let (a, b) = LoopbackConnection.pair()
        rig.host.accept(a)
        XCTAssertEqual(OnlineSession.join(peerID: "lan", name: "Lan", connection: b).status, .lobby)
        // 回線が戻ったら再試行で開ける（コードは同じ）
        relay.isReachable = true
        rig.host.retryRelay()
        XCTAssertEqual(rig.host.relayStatus, .ready)
        XCTAssertEqual(rig.code, code)
    }

    func testHostLeaveTellsGuestsThenClosesRelay() async {
        let rig = makeHost()
        let code = rig.code
        let guest = join(rig, id: "guest")
        XCTAssertEqual(guest.status, .lobby)
        rig.host.leave()
        guard case .disconnected(let reason) = guest.status else { return XCTFail("\(guest.status)") }
        XCTAssertEqual(reason, L("ホストが部屋を閉じました", "The host closed the room"), "退出の知らせが先に届く")
        // 送り切ってから中継を閉じる（中継から部屋のホストが消える）
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while rig.relay.hasHost(code) && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(rig.relay.hasHost(code))
    }

    func testRejectedGuestIsKickedAfterReason() async {
        let rig = makeHost()
        let conn = guestConnection(rig)
        var received: [OnlineMessage] = []
        conn.onMessage = { received.append($0) }
        conn.start()
        conn.send(.hello(OnlineHello(peerID: "x", name: "X", protocolVersion: OnlineProtocol.version + 1)))
        guard case .reject? = received.last else { return XCTFail("版数違いは理由を受け取る: \(received)") }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while conn.state == .ready && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(conn.state, .failed(RelayCloseCode.closedByHost.message), "ホストの KICK で 4002")
        XCTAssertEqual(rig.relay.guestCount(rig.code), 0)
    }
}
