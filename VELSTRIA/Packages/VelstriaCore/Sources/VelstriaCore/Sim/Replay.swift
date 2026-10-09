import Foundation

// 担当: core-economy
// リプレイ = 設定（シード含む）+ 人間入力列。AI は決定論なので再シミュレーションで完全再現できる。

public struct ReplayFrame: Codable, Hashable, Sendable {
    public var tick: Int
    public var commands: [HeroCommand]

    public init(tick: Int, commands: [HeroCommand]) {
        self.tick = tick
        self.commands = commands
    }
}

public struct ReplayData: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var config: MatchConfig
    public var frames: [ReplayFrame]
    public var finalTick: Int
    public var summary: MatchSummary?
    /// 試合の年表（キル・構造物・目標・ゴールド推移）。古いファイルや記録しなかった場合は nil（再生中に作り直す）。
    public var timeline: ReplayTimeline?

    public init(formatVersion: Int = ReplayData.currentFormatVersion, config: MatchConfig, frames: [ReplayFrame],
                finalTick: Int, summary: MatchSummary?, timeline: ReplayTimeline? = nil) {
        self.formatVersion = formatVersion
        self.config = config
        self.frames = frames
        self.finalTick = finalTick
        self.summary = summary
        self.timeline = timeline
    }

    /// 現在のシミュレーションで再生できるか（ルール版数・形式が一致）。
    public var isPlayable: Bool {
        formatVersion == ReplayData.currentFormatVersion && config.simVersion == MatchConfig.currentSimVersion
    }

    /// 試合時間（秒）。
    public var duration: Double { Double(finalTick) * Balance.dt }
}

public final class ReplayRecorder {
    public private(set) var config: MatchConfig
    public private(set) var frames: [ReplayFrame] = []
    public private(set) var lastTick = 0

    public init(config: MatchConfig) {
        self.config = config
    }

    public func record(tick: Int, commands: [HeroCommand]) {
        // 観戦のシークで戻っても、記録の終わりは到達した最も先の tick（観戦の記録は入力が無いので途中の列は変わらない）
        lastTick = max(lastTick, tick)
        if !commands.isEmpty { frames.append(ReplayFrame(tick: tick, commands: commands)) }
    }

    /// 年表（記録側が step 毎に作ったもの）。finish でリプレイに同梱する。
    public var timeline: ReplayTimeline?
    /// 記録が試合の途中から・途中が抜けている（オンラインの再同期など）。再現できないので保存しない。
    public private(set) var isIncomplete = false

    /// 記録を不完全にする（状態を外から置き換えた時など）。
    public func markIncomplete() { isIncomplete = true }

    public func finish(summary: MatchSummary?) -> ReplayData {
        ReplayData(formatVersion: ReplayData.currentFormatVersion, config: config, frames: frames,
                   finalTick: lastTick, summary: summary, timeline: timeline)
    }
}

/// リプレイ再生。記録された人間入力を該当 tick に投入しながら同じ config でシミュレーションし直す。
///
/// ```
/// let player = ReplayPlayer(data: replay)
/// while !player.isFinished { let events = player.stepOnce() }
/// ```
/// シークは再シミュレーションで行う。再生中に keyframeInterval tick 毎の状態を保存しておき、
/// 後退（または保存済み区間への前進）はそのキーフレームから再開するので、長い試合でも待ち時間が一定に収まる。
public final class ReplayPlayer {
    /// 既定のキーフレーム間隔（tick）。30 秒毎（状態 1 つ約 200KB。25 分の試合で 50 個・約 10MB）。
    public static let defaultKeyframeInterval = 900

    public let data: ReplayData
    /// キーフレームの間隔（tick）。
    public let keyframeInterval: Int
    public private(set) var simulation: Simulation
    private let master: MasterData
    private let map: MapDefinition
    /// tick 昇順に並べたフレーム。
    private let frames: [ReplayFrame]
    /// 次に投入するフレームの位置。
    private var cursor = 0
    /// 再生中に保存した状態（tick 昇順・重複なし）。
    private var keyframes: [SimState] = []

    public init(data: ReplayData, master: MasterData = .shared, map: MapDefinition? = nil,
                keyframeInterval: Int = ReplayPlayer.defaultKeyframeInterval) {
        self.data = data
        self.keyframeInterval = max(1, keyframeInterval)
        self.master = master
        // マップは保存しないので記録時の mode から導出する（乱闘リプレイのデシンク防止）。
        self.map = map ?? MapDefinition.map(for: data.config.mode)
        self.frames = data.frames.enumerated()
            .sorted { $0.element.tick != $1.element.tick ? $0.element.tick < $1.element.tick : $0.offset < $1.offset }
            .map(\.element)
        self.simulation = Simulation(config: data.config, master: master, map: self.map)
    }

    public var state: SimState { simulation.state }
    public var currentTick: Int { simulation.state.tick }
    public var finalTick: Int { data.finalTick }
    public var isFinished: Bool { simulation.isEnded || currentTick >= data.finalTick }
    /// 再生位置 0...1（シークバー）。
    public var progress: Double { data.finalTick > 0 ? min(1, Double(currentTick) / Double(data.finalTick)) : 1 }
    /// 保存済みキーフレームの tick（テスト・デバッグ用）。
    var keyframeTicks: [Int] { keyframes.map(\.tick) }

    /// 次の tick の記録入力。
    private func takeCommands(forTick tick: Int) -> [HeroCommand] {
        while cursor < frames.count, frames[cursor].tick < tick { cursor += 1 }
        var out: [HeroCommand] = []
        while cursor < frames.count, frames[cursor].tick == tick {
            out += frames[cursor].commands
            cursor += 1
        }
        return out
    }

    /// 1 tick 進め、その tick のイベントを返す（終了済みなら空）。
    @discardableResult
    public func stepOnce() -> [SimEvent] {
        guard !isFinished else { return [] }
        let commands = takeCommands(forTick: currentTick + 1)
        let events = simulation.step(commands: commands)
        let t = currentTick
        if t % keyframeInterval == 0, t > (keyframes.last?.tick ?? 0) {
            keyframes.append(simulation.state)
        }
        return events
    }

    /// 指定 tick へ移動する（途中のイベントは破棄）。
    /// 目標以前で最も新しいキーフレームが現在位置より先にあるか、後退する場合はそこ（無ければ先頭）から再シミュレーションする。
    public func seek(toTick tick: Int) {
        let target = max(0, min(tick, data.finalTick))
        let keyframe = keyframes.last { $0.tick <= target }
        if target < currentTick || (keyframe?.tick ?? -1) > currentTick {
            if let keyframe {
                resume(from: keyframe)
            } else {
                restart()
            }
        }
        while currentTick < target && !isFinished { stepOnce() }
    }

    /// 先頭に戻す（保存済みキーフレームは同じ記録なので保持する）。
    public func restart() {
        simulation = Simulation(config: data.config, master: master, map: map)
        cursor = 0
    }

    private func resume(from snapshot: SimState) {
        simulation = Simulation(snapshot: snapshot, master: master, map: map)
        cursor = frames.firstIndex { $0.tick > snapshot.tick } ?? frames.count
    }
}

// MARK: - 状態ハッシュ（決定論の検証・デシンク検出）

extension SimState {
    /// ユニットの ID・種別・生死・位置・HP（0.01 単位に丸め）と主要な経済値の FNV-1a 64bit ハッシュ。
    /// 同じ config・同じ入力なら同じ値になる（プラットフォーム非依存の整数化のみ使用）。
    public func stateHash() -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ v: Int64) {
            var x = UInt64(bitPattern: v)
            for _ in 0..<8 {
                h ^= x & 0xff
                h = h &* 0x0000_0100_0000_01b3
                x >>= 8
            }
        }
        func mix(_ d: Double) {
            guard d.isFinite else { mix(Int64.min); return }
            let scaled = (d * 100).rounded()
            mix(Int64(max(-9.0e18, min(9.0e18, scaled))))
        }
        mix(Int64(tick))
        mix(Int64(phase.rawValue))
        mix(Int64(winner?.rawValue ?? -1))
        mix(Int64(units.count))
        for u in units {
            mix(Int64(u.id))
            mix(Int64(u.kind.rawValue))
            mix(Int64(u.team.rawValue))
            mix(Int64(u.isAlive ? 1 : 0))
            mix(u.pos.x)
            mix(u.pos.y)
            mix(u.hp)
            if let hero = u.hero {
                mix(Int64(hero.level))
                mix(hero.xp)
                mix(hero.gold)
                mix(Int64(hero.items.count))
                for id in hero.items { for b in id.utf8 { mix(Int64(b)) } }
                // キット層: レジスタ・形態・窓の段・予約タイマー・突進の有無
                if let kit = hero.kit {
                    for v in kit.ints { mix(Int64(v)) }
                    for v in kit.reals { mix(v) }
                    for v in kit.timers { mix(v) }
                    for v in kit.ids { mix(Int64(v)) }
                    mix(Int64(kit.form))
                    for w in kit.windows { mix(Int64(w.stage)); mix(w.remaining); mix(Int64(w.charges)) }
                    // 予約中のタイマー（挿入順）: 種別・残り・スロット・対象・連撃の番号
                    mix(Int64(kit.scheduled.count))
                    for t in kit.scheduled {
                        mix(Int64(t.code))
                        mix(t.remaining)
                        mix(Int64(t.slot.rawValue))
                        mix(Int64(t.targetID))
                        mix(Int64(t.index))
                    }
                    // 突進の有無と、着地で呼ぶ code
                    mix(Int64(kit.sweep == nil ? 0 : 1))
                    if let sw = kit.sweep { mix(Int64(sw.arriveCode)) }
                }
            }
            // キット層の status（mark 以降）の (kind, tag, magnitude)。キットのヒーローは全 status を混ぜる
            if !u.statuses.isEmpty {
                let all = u.hero?.kit != nil
                for st in u.statuses where all || st.kind.rawValue >= StatusKind.mark.rawValue {
                    mix(Int64(st.kind.rawValue))
                    for b in st.tag.utf8 { mix(Int64(b)) }
                    mix(st.magnitude)
                }
            }
        }
        for t in teams {
            mix(Int64(t.kills))
            mix(Int64(t.towersDestroyed))
        }
        return h
    }
}
