import Foundation

/// 試合中に不変の参照データ。
public final class SimContext: @unchecked Sendable {
    public let master: MasterData
    public let map: MapDefinition
    public let nav: NavGrid
    public let config: MatchConfig

    public init(master: MasterData, map: MapDefinition = .standard, config: MatchConfig) {
        self.master = master
        self.map = map
        self.nav = NavGrid(map: map)
        self.config = config
    }
}
