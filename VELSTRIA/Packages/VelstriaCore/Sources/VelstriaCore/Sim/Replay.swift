import Foundation

// 担当: core-economy（最小実装。再生側 ReplayPlayer と決定論テストを実装すること）

public struct ReplayFrame: Codable, Hashable, Sendable {
    public var tick: Int
    public var commands: [HeroCommand]
}

/// リプレイ = 設定（シード含む）+ 人間入力列。AI は決定論なので再シミュレーションで完全再現できる。
public struct ReplayData: Codable, Hashable, Sendable {
    public var formatVersion: Int
    public var config: MatchConfig
    public var frames: [ReplayFrame]
    public var finalTick: Int
    public var summary: MatchSummary?
}

public final class ReplayRecorder {
    public private(set) var config: MatchConfig
    public private(set) var frames: [ReplayFrame] = []
    public private(set) var lastTick = 0

    public init(config: MatchConfig) {
        self.config = config
    }

    public func record(tick: Int, commands: [HeroCommand]) {
        lastTick = tick
        if !commands.isEmpty { frames.append(ReplayFrame(tick: tick, commands: commands)) }
    }

    public func finish(summary: MatchSummary?) -> ReplayData {
        ReplayData(formatVersion: 1, config: config, frames: frames, finalTick: lastTick, summary: summary)
    }
}
