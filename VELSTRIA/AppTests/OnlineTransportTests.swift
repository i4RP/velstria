import XCTest
@testable import VELSTRIA
import VelstriaCore

/// Network.framework の実装を localhost で通す（待ち受け → 接続 → 名乗り → 部屋の受信）。
@MainActor
final class OnlineTransportTests: XCTestCase {
    private func wait(timeout: TimeInterval, until condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    func testLocalhostListenConnectAndJoin() async throws {
        let host = OnlineSession.host(peerID: "host", name: "Host", roomName: "TCP Room")
        host.startListening(preferredPort: nil, advertises: false)   // OS が選ぶポート。Bonjour は使わない
        await wait(timeout: 5) { host.listenPort != nil }
        guard let port = host.listenPort else {
            throw XCTSkip("待ち受けを開けませんでした: \(host.listenError ?? "?")")
        }

        let connection = NWOnlineConnection(host: "127.0.0.1", port: port)
        let client = OnlineSession.join(peerID: "guest", name: "Guest", connection: connection)
        await wait(timeout: 5) { client.status == .lobby }
        XCTAssertEqual(client.status, .lobby)
        XCTAssertEqual(client.room.name, "TCP Room")
        XCTAssertEqual(host.room.peers.map(\.id), ["host", "guest"])

        // 操作が往復する
        let redMid = MatchFactory.onlineSeatIndex(team: .red, position: .mid)
        client.takeSeat(redMid)
        await wait(timeout: 5) { client.room.seatIndex(of: "guest") == redMid }
        XCTAssertEqual(host.room.seatIndex(of: "guest"), redMid)

        // ホストが部屋を閉じると leave が届いて切断される
        host.leave()
        await wait(timeout: 2) { !client.isConnected }
        XCTAssertFalse(client.isConnected)
        guard case .disconnected = client.status else { return XCTFail("ホストの退出で切断: \(client.status)") }
    }

    func testConnectToUnreachableAddressFailsWithinTimeout() async {
        // 誰も待ち受けていないポートへの接続は失敗で終わる（「接続中」のままにしない）
        let connection = NWOnlineConnection(host: "127.0.0.1", port: 1)
        let client = OnlineSession.join(peerID: "guest", name: "Guest", connection: connection)
        await wait(timeout: OnlineProtocol.connectTimeout + 5) { client.status != .connecting }
        guard case .disconnected = client.status else { return XCTFail("到達できない相手で失敗: \(client.status)") }
    }

    func testLargeMessageOverLocalhost() async throws {
        // 生の接続同士でスナップショットを送る
        let listener = NWOnlineListener(roomName: "raw", preferredPort: nil, advertises: false)
        var accepted: NWOnlineConnection?
        listener.onAccept = { accepted = $0 }
        var port: UInt16?
        listener.onStateChange = { if case .ready(let p) = $0 { port = p } }
        listener.start()
        await wait(timeout: 5) { port != nil }
        guard let port else { throw XCTSkip("待ち受けを開けませんでした") }

        let config = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A")], seed: 2)
        let sim = Simulation(config: config)
        for _ in 0..<60 { sim.step() }
        let state = sim.state

        let client = NWOnlineConnection(host: "127.0.0.1", port: port)
        var received: [OnlineMessage] = []
        client.onMessage = { received.append($0) }
        client.start()
        await wait(timeout: 5) { accepted != nil && client.state == .ready }
        guard let accepted else { return XCTFail("接続が受け付けられない") }
        await wait(timeout: 5) { accepted.state == .ready }
        accepted.send(.snapshot(state))
        accepted.send(.frames([ReplayFrame(tick: 61, commands: [])]))
        await wait(timeout: 10) { received.count >= 2 }
        XCTAssertEqual(received.count, 2)
        guard case .snapshot(let back)? = received.first else { return XCTFail("\(received)") }
        XCTAssertEqual(back.stateHash(), state.stateHash())
        XCTAssertEqual(received.last, .frames([ReplayFrame(tick: 61, commands: [])]))
        client.close()
        listener.stop()
    }
}
