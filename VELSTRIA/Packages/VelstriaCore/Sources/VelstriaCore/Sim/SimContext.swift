import Foundation

/// 試合中に不変の参照データ。
public final class SimContext: @unchecked Sendable {
    public let master: MasterData
    public let map: MapDefinition
    public let nav: NavGrid
    public let config: MatchConfig
    /// 序盤のジャングルの規則（敵のジャングルで被ダメ +20%・自陣のモンスターの報酬は狩猟持ちへ）を使う試合か。
    /// 両チームにプレイヤーが居て、陣地のキャンプがある地図（5v5 の試合）だけ。練習場・乱闘・スキルの検証用の空の試合では使わない。
    public let earlyJungleRules: Bool

    public init(master: MasterData, map: MapDefinition = .standard, config: MatchConfig) {
        self.master = master
        self.map = map
        // 格子の焼き込みは地図ごとに 1 回（NavGrid は不変。経路のキャッシュは決定論的な値だけを持つ）
        self.nav = NavGrid.shared(for: map)
        self.config = config
        self.earlyJungleRules = config.players.contains { $0.team == .blue } && config.players.contains { $0.team == .red }
            && map.camps.contains { $0.side != .neutral }
    }
}
