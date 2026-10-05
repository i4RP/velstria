import Foundation

// 担当: core（マジックチェス）。プレイヤーと全体状態。すべて値型・Codable・決定論。

public struct MChPlayer: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var isHuman: Bool
    public var displayName: String
    public var gold: Int
    public var hp: Int
    public var bench: [BoardUnit]
    public var board: [BoardUnit]
    public var shop: [ShopUnit]
    public var alive: Bool
    /// 脱落順位（1 が優勝）。生存中は nil。
    public var placement: Int?
    /// 直近ラウンドで受けた HP ダメージ（0 = 勝ち/引き分け）。
    public var lastDamageTaken: Int

    public init(id: Int, isHuman: Bool, displayName: String, gold: Int, hp: Int) {
        self.id = id
        self.isHuman = isHuman
        self.displayName = displayName
        self.gold = gold
        self.hp = hp
        self.bench = []
        self.board = []
        self.shop = []
        self.alive = true
        self.placement = nil
        self.lastDamageTaken = 0
    }

    public var boardCount: Int { board.count }
    public var allUnits: [BoardUnit] { board + bench }

    /// ベンチの空きがあるか。
    public func benchHasSpace() -> Bool { bench.count < MagicChessData.benchSize }
}

public struct MagicChessState: Codable, Sendable {
    public var config: MagicChessConfig
    public var round: Int
    public var phase: MagicChessPhase
    public var rng: SplitMix64
    public var players: [MChPlayer]
    /// 今ラウンドの対戦組。
    public var pairings: [MCPairing]
    public var nextInstanceID: Int
    public var winner: Int?

    public init(config: MagicChessConfig, players: [MChPlayer]) {
        self.config = config
        self.round = 0
        self.phase = .shop
        self.rng = SplitMix64(seed: config.seed)
        self.players = players
        self.pairings = []
        self.nextInstanceID = 1
        self.winner = nil
    }

    public var humanPlayer: MChPlayer? { players.first { $0.isHuman } }
    public var aliveCount: Int { players.reduce(0) { $0 + ($1.alive ? 1 : 0) } }

    public func player(_ id: Int) -> MChPlayer? { players.first { $0.id == id } }
    public func index(of id: Int) -> Int? { players.firstIndex { $0.id == id } }

    /// 順位表示用（優勝=上位）。生存は HP 降順、脱落は placement 昇順の逆（後で落ちた＝上位）。
    public var standings: [MChPlayer] {
        players.sorted { a, b in
            switch (a.alive, b.alive) {
            case (true, false): return true
            case (false, true): return false
            case (true, true): return a.hp != b.hp ? a.hp > b.hp : a.id < b.id
            case (false, false):
                let pa = a.placement ?? Int.max
                let pb = b.placement ?? Int.max
                return pa != pb ? pa < pb : a.id < b.id
            }
        }
    }

    /// 人間が属する対戦組。
    public var humanPairing: MCPairing? {
        guard let h = humanPlayer else { return nil }
        return pairings.first { $0.a == h.id || $0.b == h.id }
    }
}
