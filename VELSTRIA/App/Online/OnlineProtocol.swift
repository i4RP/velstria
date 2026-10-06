import Foundation
import VelstriaCore

// 担当: online。オンライン対戦（リッスンサーバー方式）のメッセージ定義と配線上の符号化。
//
// 方式: ホスト（参加者の 1 台）が権威シミュレーションを回す。各クライアントは自分のヒーローの入力（HeroCommand）を
// ホストへ送り、ホストは tick 毎に「その tick に適用した入力の全体」を全員へ配信する。クライアントは配信された
// 入力を同じ順で自分のシミュレーションに投入する（AI は決定論なので入力に含めない）。クライアントは一定間隔で
// 状態ハッシュを報告し、ホストと食い違えばホストが SimState のスナップショットを送って置き換える。
//
// 符号化: JSON（Codable）を 4 バイトのビッグエンディアン長で区切る（TCP のストリーム上で境界を復元する）。

/// 参加者の識別子（プロフィールの playerID。再接続で同じ座席に戻るための鍵）。
typealias OnlinePeerID = String

enum OnlineProtocol {
    /// 配線上のメッセージ形式の版数。互換性のない変更で上げる（ホストと一致しないと接続を拒否する）。
    static let version = 1
    /// Bonjour のサービス種別（Info.plist の NSBonjourServices と一致させる）。
    static let bonjourType = "_velstria._tcp"
    /// 既定の待ち受けポート（空いていなければ OS 任せ）。
    static let defaultPort: UInt16 = 47814
    /// 1 メッセージの上限（スナップショットは数百 KB。桁違いに大きければ壊れたストリームとみなす）。
    static let maxMessageBytes = 32 * 1024 * 1024
    /// 状態ハッシュを報告する間隔（tick）。
    static let hashInterval = 30
    /// クライアントの読み込み完了をホストが待つ上限（秒）。超えたら揃っていなくても開始する（遅れた参加者にはスナップショットを渡す）。
    static let loadTimeout: TimeInterval = 90
    /// 相手から何も届かない時間がこれを超えたら切断とみなす（秒）。ping は 2 秒毎なので通常は途切れない。
    static let livenessTimeout: TimeInterval = 20
    /// 接続の確立を待つ上限（秒）。相手が見つからない・ローカルネットワークが拒否された時に「接続中」のままにしない。
    static let connectTimeout: TimeInterval = 15
    /// Bonjour のサービス名の上限（UTF-8 バイト。超えると広告に失敗する）。
    static let maxServiceNameBytes = 63
    /// 座席数（5v5）。
    static let seatCount = Team.players.count * LanePosition.allCases.count
}

/// 座席のロードアウト（人間のピック）。heroID が nil なら未選択。
struct OnlineLoadout: Codable, Hashable {
    var heroID: String?
    var spells: [String] = ["BS01", "BS03"]
    var runes: [String] = []
    var skinID: String?
    var autoLevelSkills = true
}

/// ロビーの座席。peerID が nil なら AI が入る。
struct OnlineSeat: Codable, Hashable, Identifiable {
    var index: Int
    var team: Team
    var position: LanePosition
    var peerID: OnlinePeerID?
    var name: String = ""
    var loadout = OnlineLoadout()
    var ready = false

    var id: Int { index }
    var isHuman: Bool { peerID != nil }

    static func empty(_ index: Int) -> OnlineSeat {
        let s = MatchFactory.onlineSeat(index) ?? (.blue, .top)
        return OnlineSeat(index: index, team: s.team, position: s.position)
    }
}

/// 接続中の参加者（座席の有無を問わない）。
struct OnlinePeer: Codable, Hashable, Identifiable {
    var id: OnlinePeerID
    var name: String
    /// 試合のアセット読み込みを終えた（ホストが開始を待つ）。
    var loaded = false
    /// 直近の往復遅延（秒。ホストが計測）。
    var rtt: Double?
}

enum OnlineRoomPhase: Int, Codable, Hashable {
    case lobby, loading, playing, ended
}

/// 部屋の全状態。ホストが正本を持ち、変化するたびに全員へ配る（差分管理をしないので取りこぼしに強い）。
struct OnlineRoom: Codable, Hashable {
    var name: String
    var hostPeerID: OnlinePeerID
    var seats: [OnlineSeat]
    var peers: [OnlinePeer]
    var botDifficulty: Difficulty = .normal
    var phase: OnlineRoomPhase = .lobby
    /// 開始した試合の構成（loading 以降）。
    var config: MatchConfig?

    init(name: String, hostPeerID: OnlinePeerID) {
        self.name = name
        self.hostPeerID = hostPeerID
        self.seats = (0..<OnlineProtocol.seatCount).map { OnlineSeat.empty($0) }
        self.peers = []
    }

    func seat(of peerID: OnlinePeerID) -> OnlineSeat? { seats.first { $0.peerID == peerID } }
    func seatIndex(of peerID: OnlinePeerID) -> Int? { seats.firstIndex { $0.peerID == peerID } }
    func peer(_ id: OnlinePeerID) -> OnlinePeer? { peers.first { $0.id == id } }
    var humanSeats: [OnlineSeat] { seats.filter(\.isHuman) }
    /// 人間が選んだヒーロー（重複ピックの判定用）。
    var pickedHeroIDs: Set<String> { Set(humanSeats.compactMap(\.loadout.heroID)) }

    /// 開始できるか: ホストが座り、座っている人間は全員ヒーローを選んで準備完了。
    /// （ホストが座らずに始めると、権威シミュレーションを回す端末が無く部屋全体が止まる）
    var canStart: Bool {
        let humans = humanSeats
        guard !humans.isEmpty, seat(of: hostPeerID) != nil else { return false }
        return humans.allSatisfy { $0.loadout.heroID != nil && $0.ready }
    }

    /// 座席から試合構成を作る（人間のいない枠は AI）。
    func makeConfig(seed: UInt64, master: MasterData) -> MatchConfig {
        let humans = humanSeats.compactMap { s -> OnlineHumanSlot? in
            guard let hero = s.loadout.heroID else { return nil }
            return OnlineHumanSlot(team: s.team, position: s.position, heroID: hero,
                                   displayName: s.name.isEmpty ? L("プレイヤー", "Player") : s.name,
                                   spells: s.loadout.spells, runes: s.loadout.runes, skinID: s.loadout.skinID,
                                   autoLevelSkills: s.loadout.autoLevelSkills)
        }
        return MatchFactory.onlineMatch(humans: humans, botDifficulty: botDifficulty, seed: seed, master: master)
    }
}

struct OnlineHello: Codable, Hashable {
    var peerID: OnlinePeerID
    var name: String
    var protocolVersion = OnlineProtocol.version
    var simVersion = MatchConfig.currentSimVersion
}

/// 配線上のメッセージ。
enum OnlineMessage: Codable {
    // 接続
    /// クライアント → ホスト: 名乗り。
    case hello(OnlineHello)
    /// ホスト → クライアント: 受け入れ（部屋の現状を同封）。
    case welcome(room: OnlineRoom)
    /// ホスト → クライアント: 拒否（版数不一致・満員・試合中）。送信後に切断する。
    case reject(reason: String)
    // ロビー
    /// ホスト → 全員: 部屋の現状。
    case room(OnlineRoom)
    /// クライアント → ホスト: 座席に着く（-1 で立つ）。
    case takeSeat(Int)
    /// クライアント → ホスト: ピック・ロードアウト。
    case setLoadout(OnlineLoadout)
    /// クライアント → ホスト: 準備完了の切り替え。
    case setReady(Bool)
    /// ホスト → 全員: 試合開始（読み込みへ）。座席番号 = config.players の添字。
    case startMatch(config: MatchConfig)
    /// クライアント → ホスト: 戦闘画面の準備ができ、配信を受け取れる。
    case loaded
    // 戦闘
    /// クライアント → ホスト: 自分のヒーローへの入力（ホストが次の tick に適用する）。
    case input([HeroCommand])
    /// ホスト → 全員: 各 tick に適用した入力（空の tick も送る。これがクライアントの時計）。
    case frames([ReplayFrame])
    /// クライアント → ホスト: その tick を進めた後の状態ハッシュ。
    case hash(tick: Int, value: UInt64)
    /// ホスト → クライアント: 再同期用の状態。受け取ったら自分の状態を置き換える。
    case snapshot(SimState)
    /// クライアント → ホスト: 試合から抜けた（部屋には残る）。ホストはそのヒーローを AI に引き継ぐ。
    case abandonMatch
    /// ホスト → 全員: ホストが試合を途中で終えた（退出・中断）。クライアントは自分の試合も中断終了する。
    case matchAborted(reason: String)
    /// どちらか → 相手: 退出（切断の前に送る）。
    case leave
    /// 往復遅延の計測。
    case ping(UInt32)
    case pong(UInt32)
}

/// SimState は Equatable でないので、スナップショットは tick と状態ハッシュで比べる（テスト・重複判定用）。
extension OnlineMessage: Equatable {
    static func == (a: OnlineMessage, b: OnlineMessage) -> Bool {
        switch (a, b) {
        case (.hello(let x), .hello(let y)): return x == y
        case (.welcome(let x), .welcome(let y)): return x == y
        case (.reject(let x), .reject(let y)): return x == y
        case (.room(let x), .room(let y)): return x == y
        case (.takeSeat(let x), .takeSeat(let y)): return x == y
        case (.setLoadout(let x), .setLoadout(let y)): return x == y
        case (.setReady(let x), .setReady(let y)): return x == y
        case (.startMatch(let x), .startMatch(let y)): return x == y
        case (.loaded, .loaded), (.leave, .leave), (.abandonMatch, .abandonMatch): return true
        case (.matchAborted(let x), .matchAborted(let y)): return x == y
        case (.input(let x), .input(let y)): return x == y
        case (.frames(let x), .frames(let y)): return x == y
        case (.hash(let t1, let v1), .hash(let t2, let v2)): return t1 == t2 && v1 == v2
        case (.snapshot(let x), .snapshot(let y)): return x.tick == y.tick && x.stateHash() == y.stateHash()
        case (.ping(let x), .ping(let y)), (.pong(let x), .pong(let y)): return x == y
        default: return false
        }
    }
}

/// 長さ区切りの符号化（4 バイト ビッグエンディアンの長さ + JSON）。ストリームの途中で切れても復元できる。
struct OnlineFramer {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()
    private static let decoder = JSONDecoder()

    private var buffer = Data()

    init() {}

    static func encode(_ message: OnlineMessage) throws -> Data {
        let body = try encoder.encode(message)
        var out = Data(capacity: body.count + 4)
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(body)
        return out
    }

    static func decode(_ body: Data) throws -> OnlineMessage {
        try decoder.decode(OnlineMessage.self, from: body)
    }

    enum FramingError: Error, Equatable {
        case oversized(Int)
    }

    /// 受信データを追加し、完結したメッセージをすべて返す。不完全な末尾は次回へ持ち越す。
    mutating func feed(_ data: Data) throws -> [OnlineMessage] {
        buffer.append(data)
        var out: [OnlineMessage] = []
        while buffer.count >= 4 {
            let length = buffer.withUnsafeBytes { raw -> Int in
                let b = raw.bindMemory(to: UInt8.self)
                return Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            }
            guard length <= OnlineProtocol.maxMessageBytes else {
                buffer.removeAll()
                throw FramingError.oversized(length)
            }
            guard buffer.count >= 4 + length else { break }
            let body = buffer.subdata(in: 4..<(4 + length))
            buffer.removeSubrange(0..<(4 + length))
            out.append(try Self.decode(body))
        }
        return out
    }

    /// 未処理のバイト数（テスト用）。
    var pendingBytes: Int { buffer.count }
}
