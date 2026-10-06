import Foundation
import VelstriaCore

// 担当: online。オンライン対戦（リッスンサーバー方式）のメッセージ定義と配線上の符号化。
//
// 方式: ホスト（参加者の 1 台）が権威シミュレーションを回す。各クライアントは自分のヒーローの入力（HeroCommand）を
// ホストへ送り、ホストは tick 毎に「その tick に適用した入力の全体」を全員へ配信する。クライアントは配信された
// 入力を同じ順で自分のシミュレーションに投入する（AI は決定論なので入力に含めない）。クライアントは一定間隔で
// 状態ハッシュを報告し、ホストと食い違えばホストが SimState のスナップショットを送って置き換える。
//
// 観戦（v2）: 座らない参加者は観戦席（OnlinePeer.role == .spectator）に入れる。観戦者への配信はホストが遅延を掛け
// （部屋の設定 spectatorDelayTicks、既定 30 秒。ゴースティング＝観戦者が選手へ敵の位置を教えること の対策）、
// 途中参加・再同期の基準も「遅延済みの範囲のキーフレーム」だけを渡す（生の状態は観戦者へ送らない）。
// ホストは座らずに実況（キャスター）として権威シミュレーションを回すこともできる（ホスト自身は遅延なし）。
//
// 符号化: JSON（Codable）を 4 バイトのビッグエンディアン長で区切る（TCP のストリーム上で境界を復元する）。

/// 参加者の識別子（プロフィールの playerID。再接続で同じ座席に戻るための鍵）。
typealias OnlinePeerID = String

enum OnlineProtocol {
    /// 配線上のメッセージ形式の版数。互換性のない変更で上げる（ホストと一致しないと接続を拒否する）。
    /// 2: 観戦（役割・観戦メッセージ・遅延配信）。名乗り（OnlineHello）は版数の照合より先に復号するので、追加項目は任意にする。
    static let version = 2
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

    // MARK: 観戦
    /// 選手（観戦席でない参加者。ホストを含む）の上限。座席数と同じ。
    static let maxPlayers = seatCount
    /// 観戦席の上限（ホストの実況は数えない）。観戦者毎に配信と途中参加の基準状態を送るので、ホスト端末の負荷で決めた。
    static let maxSpectators = 8
    /// 観戦の遅延の選択肢（秒）。0 = 遅延なし（身内の部屋向け）。
    static let spectatorDelayOptions = [0, 15, 30, 60]
    /// 既定の遅延（秒）。MOBA では 15 秒前の敵の位置でもまだ価値があるので、ゴースティング対策を優先して 30 秒。
    static let defaultSpectatorDelaySeconds = 30
    /// 遅延の上限（tick）。
    static let maxSpectatorDelayTicks = ticks(seconds: spectatorDelayOptions.max() ?? 60)
    /// 観戦の途中参加・再同期の基準にするキーフレームの間隔（tick。10 秒。参加直後に追いかける量の上限になる）。
    static let spectatorKeyframeInterval = 300
    /// 観戦者への配信をまとめて送る間隔（秒）。遅延しているので細かく送る必要がない。
    static let spectatorReleaseInterval: TimeInterval = 0.1
    /// 状態のずれによるスナップショットの最短間隔（秒）。ずれが続いても毎秒は送らない（ホストの負荷と帯域）。
    static let spectatorSnapshotInterval: TimeInterval = 5
    static let playerSnapshotInterval: TimeInterval = 2

    static func ticks(seconds: Int) -> Int { Int((Double(seconds) * Balance.tickRate).rounded()) }
}

/// 部屋での役割。観戦席は試合が始まると観戦画面が開く（座席には座れない）。
enum OnlinePeerRole: String, Codable, Hashable {
    case player
    case spectator
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
    /// 部屋での役割（観戦席なら試合開始時に観戦画面が開く）。ホストの観戦席 = 実況（キャスター）。
    var role: OnlinePeerRole = .player
    /// いま試合を観戦している（ホストが配信中。ホストの実況を含む）。選手にも人数を見せる。
    var isWatching = false
    /// 座席を保ったまま試合から抜けた（AI が操作中。「試合に戻る」「観戦する」を選べる）。
    var leftMatch = false
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
    /// 観戦を許可する（ホストの設定。ロビーでだけ変えられる）。
    var allowsSpectators = true
    /// 観戦者への配信の遅延（tick。ロビーでだけ変えられる。試合中に縮めると遅延の意味がなくなる）。
    var spectatorDelayTicks = OnlineProtocol.ticks(seconds: OnlineProtocol.defaultSpectatorDelaySeconds)

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
    /// 選手の参加者（観戦席でない。座っていない人を含む）。
    var players: [OnlinePeer] { peers.filter { $0.role == .player } }
    /// 観戦席の参加者（ホストの実況を除く）。
    var spectators: [OnlinePeer] { peers.filter { $0.role == .spectator && $0.id != hostPeerID } }
    /// ホストが座らずに実況（キャスター）として試合を回す。
    var hostIsCaster: Bool { peer(hostPeerID)?.role == .spectator }
    /// いま試合を観戦している人数（ホストの実況を含む）。
    var watchingCount: Int { phase == .lobby ? 0 : peers.filter(\.isWatching).count }
    /// 観戦者への遅延（秒）。
    var spectatorDelaySeconds: Double { Double(spectatorDelayTicks) * Balance.dt }
    /// 人間が選んだヒーロー（重複ピックの判定用）。
    var pickedHeroIDs: Set<String> { Set(humanSeats.compactMap(\.loadout.heroID)) }

    /// 開始できるか: ホストが座るか実況（キャスター）になっていて、座っている人間が 1 人以上、全員ヒーローを選んで準備完了。
    /// （権威シミュレーションはホストの端末が回す。座らずに観戦もしないホストでは、回す端末が無く部屋全体が止まる）
    var canStart: Bool {
        let humans = humanSeats
        guard !humans.isEmpty, seat(of: hostPeerID) != nil || hostIsCaster else { return false }
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
    /// 観戦席で入りたい（試合中なら途中から観戦する）。v1 の名乗りには無いので任意（版数の照合より先に復号する）。
    var wantsSpectate: Bool?
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
    // 観戦（v2）
    /// クライアント → ホスト: ロビーで観戦席に移る（true。座席は立つ）/ 選手に戻る（false）。ホスト自身は実況になる。
    case setSpectator(Bool)
    /// クライアント → ホスト: 進行中の試合を観戦したい（座っていない、または試合から抜けた参加者）。
    case requestSpectate
    /// ホスト → 観戦者: 観戦の開始。構成・遅延（tick）・基準の目安（いま観戦を始めると見え始める tick。実際の基準は
    /// spectateLoaded の後に届くスナップショット）。観戦画面を用意したら spectateLoaded を返す。
    case spectateMatch(config: MatchConfig, delayTicks: Int, baseTick: Int)
    /// クライアント → ホスト: 観戦画面の準備ができた（基準の状態と遅延済みの配信を送ってよい）。
    case spectateLoaded
    /// クライアント → ホスト: 観戦をやめた / 観戦の案内を断った（配信を止める。観戦席の役割はそのまま）。
    case stopSpectating
    /// ホスト → 観戦者: 試合が終わった。finalTick までの配信を送り終えた（遅延分の残りは前倒しで届く）。
    case matchFinished(finalTick: Int)
    /// ホスト → クライアント: 観戦の求めを断った（理由を表示する）。
    case spectateDenied(reason: String)
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
        case (.setSpectator(let x), .setSpectator(let y)): return x == y
        case (.requestSpectate, .requestSpectate), (.spectateLoaded, .spectateLoaded), (.stopSpectating, .stopSpectating): return true
        case (.spectateMatch(let c1, let d1, let b1), .spectateMatch(let c2, let d2, let b2)): return c1 == c2 && d1 == d2 && b1 == b2
        case (.matchFinished(let x), .matchFinished(let y)): return x == y
        case (.spectateDenied(let x), .spectateDenied(let y)): return x == y
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
        framed(try encoder.encode(message))
    }

    /// バックグラウンドのスレッドから符号化する（共有のエンコーダを使わない）。観戦者へのスナップショット（数百 KB）用。
    static func encodeDetached(_ message: OnlineMessage) throws -> Data {
        framed(try JSONEncoder().encode(message))
    }

    private static func framed(_ body: Data) -> Data {
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
