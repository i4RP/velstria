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
        // 格子の焼き込みは地図ごとに 1 回（NavGrid は不変。経路のキャッシュは決定論的な値だけを持つ）
        self.nav = NavGrid.shared(for: map)
        self.config = config
    }
}
