import XCTest
import Network
@testable import VELSTRIA
import VelstriaCore

/// 配線上の符号化（長さ区切り + JSON）と部屋モデル。
final class OnlineProtocolTests: XCTestCase {
    private func sampleMessages() -> [OnlineMessage] {
        var room = OnlineRoom(name: "部屋", hostPeerID: "host")
        room.seats[2].peerID = "host"
        room.seats[2].name = "Host"
        room.seats[2].loadout = OnlineLoadout(heroID: "H001", spells: ["BS01", "BS03"], runes: ["R001"], skinID: nil, autoLevelSkills: false)
        room.peers = [OnlinePeer(id: "host", name: "Host", loaded: true, rtt: 0.012)]
        let config = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "Host")], seed: 9)
        let state = Simulation(config: config).state
        return [
            .hello(OnlineHello(peerID: "guest", name: "Guest")),
            .welcome(room: room),
            .reject(reason: "満員です"),
            .room(room),
            .takeSeat(7),
            .setLoadout(OnlineLoadout(heroID: "H002")),
            .setReady(true),
            .startMatch(config: config),
            .loaded,
            .input([HeroCommand(heroID: 12, command: .move(direction: Vec2(1, 0)), sequence: 3),
                    HeroCommand(heroID: 12, command: .castSkill(slot: .skill1, target: .point(Vec2(10, 20))), sequence: 4)]),
            .frames([ReplayFrame(tick: 1, commands: []), ReplayFrame(tick: 2, commands: [HeroCommand(heroID: 12, command: .recall)])]),
            .hash(tick: 30, value: 0xDEAD_BEEF_0000_0001),
            .snapshot(state),
            .leave,
            .ping(7),
            .pong(7),
            // 観戦（v2）
            .hello(OnlineHello(peerID: "watcher", name: "W", wantsSpectate: true)),
            .setSpectator(true),
            .setSpectator(false),
            .requestSpectate,
            .spectateMatch(config: config, delayTicks: 900, baseTick: 300),
            .spectateLoaded,
            .stopSpectating,
            .matchFinished(finalTick: 4321),
            .spectateDenied(reason: "観戦席が満員です"),
            .matchAborted(reason: "ホストが試合を終了しました"),
        ]
    }

    func testEveryMessageRoundTrips() throws {
        var framer = OnlineFramer()
        for m in sampleMessages() {
            let data = try OnlineFramer.encode(m)
            let out = try framer.feed(data)
            XCTAssertEqual(out.count, 1)
            if case .snapshot(let s) = m, case .snapshot(let back)? = out.first {
                XCTAssertEqual(s.stateHash(), back.stateHash())
                XCTAssertEqual(s.tick, back.tick)
                XCTAssertEqual(back.index(of: s.units[3].id), 3, "復号した状態の索引が使える")
            } else {
                XCTAssertEqual(out.first, m)
            }
            XCTAssertEqual(framer.pendingBytes, 0)
        }
    }

    func testFramerReassemblesArbitraryChunks() throws {
        let messages = sampleMessages().filter { if case .snapshot = $0 { return false } else { return true } }
        var stream = Data()
        for m in messages { stream.append(try OnlineFramer.encode(m)) }
        // 1 バイトずつ・不揃いな塊・一括 のどれでも同じ列に戻る
        for chunk in [1, 3, 17, 1000, stream.count] {
            var framer = OnlineFramer()
            var out: [OnlineMessage] = []
            var i = 0
            while i < stream.count {
                let end = min(stream.count, i + chunk)
                out += try framer.feed(stream.subdata(in: i..<end))
                i = end
            }
            XCTAssertEqual(out, messages, "chunk \(chunk)")
            XCTAssertEqual(framer.pendingBytes, 0)
        }
    }

    func testRoomWithSpectatorsRoundTrips() throws {
        var room = OnlineRoom(name: "部屋", hostPeerID: "host")
        room.peers = [OnlinePeer(id: "host", name: "Host", role: .spectator, isWatching: true),
                      OnlinePeer(id: "w", name: "W", role: .spectator),
                      OnlinePeer(id: "p", name: "P", leftMatch: true)]
        room.allowsSpectators = false
        room.spectatorDelayTicks = OnlineProtocol.ticks(seconds: 15)
        var framer = OnlineFramer()
        let out = try framer.feed(try OnlineFramer.encode(.room(room)))
        XCTAssertEqual(out, [.room(room)])
        guard case .room(let back)? = out.first else { return XCTFail() }
        XCTAssertTrue(back.hostIsCaster)
        XCTAssertEqual(back.spectators.map(\.id), ["w"], "ホストの実況は観戦席の数に入れない")
        XCTAssertEqual(back.players.map(\.id), ["p"])
        XCTAssertEqual(back.spectatorDelaySeconds, 15, accuracy: 1e-9)
        XCTAssertEqual(back.peer("p")?.leftMatch, true)
    }

    func testHelloFromOlderAppStillDecodes() throws {
        // 名乗りは版数の照合より先に復号する: v1 の名乗り（wantsSpectate なし）も復号でき、版数で断れる
        let v1 = #"{"hello":{"_0":{"peerID":"old","name":"Old","protocolVersion":1,"simVersion":4}}}"#
        let m = try OnlineFramer.decode(Data(v1.utf8))
        guard case .hello(let hello) = m else { return XCTFail("\(m)") }
        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertNil(hello.wantsSpectate)
        XCTAssertNotEqual(hello.protocolVersion, OnlineProtocol.version)
        // 観戦の希望が無い名乗りは wantsSpectate を送らない（古い版のホストでも同じ形）
        let encoded = String(decoding: try JSONEncoder().encode(OnlineHello(peerID: "a", name: "A")), as: UTF8.self)
        XCTAssertFalse(encoded.contains("wantsSpectate"))
    }

    func testDetachedEncodingMatchesSharedEncoder() throws {
        let config = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A")], seed: 3)
        let state = Simulation(config: config).state
        var framer = OnlineFramer()
        let out = try framer.feed(try OnlineFramer.encodeDetached(.snapshot(state)))
        guard case .snapshot(let back)? = out.first else { return XCTFail() }
        XCTAssertEqual(back.stateHash(), state.stateHash())
    }

    func testOversizedFrameIsRejected() {
        var framer = OnlineFramer()
        var header = Data()
        var length = UInt32(OnlineProtocol.maxMessageBytes + 1).bigEndian
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
        XCTAssertThrowsError(try framer.feed(header))
        XCTAssertEqual(framer.pendingBytes, 0)
    }

    func testRoomStartRulesAndConfig() {
        var room = OnlineRoom(name: "r", hostPeerID: "h")
        XCTAssertFalse(room.canStart, "誰も座っていない")
        let blueMid = MatchFactory.onlineSeatIndex(team: .blue, position: .mid)
        let redTop = MatchFactory.onlineSeatIndex(team: .red, position: .top)
        room.seats[blueMid].peerID = "h"
        room.seats[blueMid].name = "Host"
        XCTAssertFalse(room.canStart, "ヒーロー未選択")
        room.seats[blueMid].loadout.heroID = "H005"
        XCTAssertFalse(room.canStart, "準備未完了")
        room.seats[blueMid].ready = true
        XCTAssertTrue(room.canStart)
        room.seats[redTop].peerID = "g"
        room.seats[redTop].name = "Guest"
        room.seats[redTop].loadout.heroID = "H006"
        XCTAssertFalse(room.canStart, "参加者が準備未完了")
        room.seats[redTop].ready = true
        room.botDifficulty = .hard
        let config = room.makeConfig(seed: 100, master: .shared)
        XCTAssertEqual(config.mode, .online)
        XCTAssertEqual(config.players[blueMid].heroID, "H005")
        XCTAssertEqual(config.players[blueMid].displayName, "Host")
        XCTAssertEqual(config.players[redTop].heroID, "H006")
        XCTAssertEqual(config.players[redTop].controller, .human)
        XCTAssertEqual(config.players.filter { $0.controller == .bot }.count, 8)
        XCTAssertTrue(config.players.filter { $0.controller == .bot }.allSatisfy { $0.botDifficulty == .hard })
        XCTAssertEqual(room.pickedHeroIDs, ["H005", "H006"])
    }

    func testHostMustSitOrCastToStart() {
        // B1: 座っていないホストは開始できない（権威シミュレーションを回す端末が無い）。実況（観戦席）なら開始できる
        var room = OnlineRoom(name: "r", hostPeerID: "h")
        room.peers = [OnlinePeer(id: "h", name: "Host"), OnlinePeer(id: "g", name: "Guest")]
        let redTop = MatchFactory.onlineSeatIndex(team: .red, position: .top)
        room.seats[redTop].peerID = "g"
        room.seats[redTop].loadout.heroID = "H006"
        room.seats[redTop].ready = true
        XCTAssertFalse(room.canStart, "ホストが座らず実況でもない")
        room.peers[0].role = .spectator
        XCTAssertTrue(room.hostIsCaster)
        XCTAssertTrue(room.canStart, "ホストの実況で開始できる")
        room.seats[redTop] = OnlineSeat.empty(redTop)
        XCTAssertFalse(room.canStart, "選手が誰も座っていない")
    }

    func testAdvertisementEntries() {
        var room = OnlineRoom(name: "r", hostPeerID: "h")
        room.peers = [OnlinePeer(id: "h", name: "Host"), OnlinePeer(id: "w", name: "W", role: .spectator)]
        var txt = OnlineAdvertisement.entries(for: room)
        XCTAssertEqual(txt[OnlineAdvertisement.phaseKey], "lobby")
        XCTAssertEqual(txt[OnlineAdvertisement.watchKey], "1")
        XCTAssertEqual(txt[OnlineAdvertisement.playersKey], "1")
        XCTAssertEqual(txt[OnlineAdvertisement.spectatorsKey], "1")
        room.phase = .playing
        room.allowsSpectators = false
        txt = OnlineAdvertisement.entries(for: room)
        XCTAssertEqual(txt[OnlineAdvertisement.phaseKey], "match")
        XCTAssertEqual(txt[OnlineAdvertisement.watchKey], "0")
        txt["v"] = "\(OnlineProtocol.version)"
        txt["name"] = "r"
        let found = NWOnlineBrowser.Room(name: "r", endpoint: .hostPort(host: "127.0.0.1", port: 1), txt: txt)
        XCTAssertTrue(found.inMatch)
        XCTAssertFalse(found.allowsSpectators)
        XCTAssertTrue(found.isCompatible)
        XCTAssertEqual(found.players, 1)
        let old = NWOnlineBrowser.Room(name: "r", endpoint: .hostPort(host: "127.0.0.1", port: 1), txt: ["v": "1"])
        XCTAssertFalse(old.isCompatible, "古い版の部屋は入れない")
    }

    func testAddressParsing() {
        XCTAssertEqual(OnlineNetwork.parseAddress("192.168.1.10:5000")?.host, "192.168.1.10")
        XCTAssertEqual(OnlineNetwork.parseAddress("192.168.1.10:5000")?.port, 5000)
        XCTAssertEqual(OnlineNetwork.parseAddress(" 192.168.1.10 ")?.port, OnlineProtocol.defaultPort)
        XCTAssertEqual(OnlineNetwork.parseAddress("host.local:1")?.host, "host.local")
        XCTAssertNil(OnlineNetwork.parseAddress(""))
        XCTAssertNil(OnlineNetwork.parseAddress(":5000"))
        XCTAssertNil(OnlineNetwork.parseAddress("a:b"))
    }

    func testBattleLaunchLocalTeam() {
        let config = MatchFactory.onlineMatch(humans: [
            OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A"),
            OnlineHumanSlot(team: .red, position: .mid, heroID: "H002", displayName: "B"),
        ], seed: 1)
        let redMid = MatchFactory.onlineSeatIndex(team: .red, position: .mid)
        XCTAssertEqual(BattleLaunch(config: config, onlineSeat: redMid).localTeam, .red)
        XCTAssertEqual(BattleLaunch(config: config).localTeam, .blue, "座席なしは最初の人間")
        XCTAssertTrue(BattleLaunch(config: config, onlineSeat: redMid).isOnline)
    }
}
