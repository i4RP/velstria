import Foundation

// 担当: 統合（契約）。観戦・リプレイの年表（キル・構造物・目標・全滅と、チームのゴールド/経験値の推移）。
//
// - シミュレーションの外側の記録（SimState には載せない）。step の戻り値のイベントと step 後の状態だけから作るので、
//   同じ config・同じ入力なら同じ年表になる（決定論）。
// - ライブ観戦・リプレイのシーク・ゴールド差グラフ・イベント一覧・自動カメラが共通で使う。
// - ReplayData.timeline として保存できる（古いファイルは nil。再生中に作り直す）。

/// 年表の出来事の種類。
public enum TimelineEventKind: Codable, Hashable, Sendable {
    /// ヒーローの撃破。killerTeam = 倒した側（処刑なら nil）。
    case kill(victimID: EntityID, killerID: EntityID?, assistIDs: [EntityID], killerTeam: Team?,
              isFirstBlood: Bool, multiKill: Int, isShutdown: Bool)
    /// 構造物の破壊。team = 失った側。
    case structure(team: Team, kind: UnitKind, lane: Lane?, tier: TowerTier?, killerID: EntityID?)
    /// 中立の大型目標（番人・星喰竜・古環の巨像）。team = 取った側。
    case objective(kind: MonsterKind, team: Team, killerID: EntityID?)
    /// 全滅（team = 全滅させた側）。
    case ace(team: Team)
    /// 試合終了。
    case matchEnd(winner: Team?, reason: EndReason)
}

/// 年表の 1 項目。
public struct TimelineEvent: Codable, Hashable, Sendable {
    public var tick: Int
    public var kind: TimelineEventKind
    /// 起きた場所（キル = 倒されたヒーローの位置、構造物 = その位置）。不明なら nil。
    public var pos: Vec2?

    public init(tick: Int, kind: TimelineEventKind, pos: Vec2?) {
        self.tick = tick
        self.kind = kind
        self.pos = pos
    }

    public var time: Double { Double(tick) * Balance.dt }

    /// 有利になった側（キル = 倒した側、構造物 = 壊した側、目標 = 取った側、全滅 = 全滅させた側）。
    public var creditedTeam: Team? {
        switch kind {
        case .kill(_, _, _, let killerTeam, _, _, _): return killerTeam
        case .structure(let team, _, _, _, _): return team.opponent
        case .objective(_, let team, _): return team
        case .ace(let team): return team
        case .matchEnd(let winner, _): return winner
        }
    }

    /// 重要度（0〜1。自動カメラ・イベント一覧の強調・シークバーの印の大きさに使う）。
    public var weight: Double {
        switch kind {
        case .kill(_, _, _, _, let fb, let multi, let shutdown):
            var w = 0.45
            if fb { w += 0.15 }
            if multi >= 2 { w += 0.1 * Double(min(4, multi - 1)) }
            if shutdown { w += 0.1 }
            return min(1, w)
        case .structure(_, let kind, _, let tier, _):
            if kind == .core { return 1 }
            switch tier {
            case .base?: return 0.75
            case .inner?: return 0.65
            default: return 0.55
            }
        case .objective(let kind, _, _):
            switch kind {
            case .astralWyrm, .ancientColossus: return 0.9
            case .blueSentinel, .redSentinel: return 0.5
            case .campLarge, .campSmall: return 0.2
            }
        case .ace: return 0.85
        case .matchEnd: return 1
        }
    }
}

/// 一定間隔のチーム指標（ゴールド差・経験値差のグラフ用）。
public struct TimelineSample: Codable, Hashable, Sendable {
    public var tick: Int
    public var blueGold: Double
    public var redGold: Double
    public var blueXP: Double
    public var redXP: Double
    public var blueKills: Int
    public var redKills: Int
    public var blueTowers: Int
    public var redTowers: Int

    public init(tick: Int, blueGold: Double, redGold: Double, blueXP: Double, redXP: Double,
                blueKills: Int, redKills: Int, blueTowers: Int, redTowers: Int) {
        self.tick = tick
        self.blueGold = blueGold
        self.redGold = redGold
        self.blueXP = blueXP
        self.redXP = redXP
        self.blueKills = blueKills
        self.redKills = redKills
        self.blueTowers = blueTowers
        self.redTowers = redTowers
    }

    /// Blue から見たゴールド差（正 = Blue 有利）。
    public var goldDiff: Double { blueGold - redGold }
    /// Blue から見た経験値差。
    public var xpDiff: Double { blueXP - redXP }

    /// 状態から作る（決定論: 配列の添字順にだけ集計する）。
    public init(state s: SimState) {
        var gold: [Double] = [0, 0]
        var xp: [Double] = [0, 0]
        for i in s.heroIndices {
            let u = s.units[i]
            guard let h = u.hero, u.team != .neutral else { continue }
            gold[u.team.rawValue] += Balance.startingGold + h.score.goldEarned
            xp[u.team.rawValue] += HeroGrowth.totalXP(toReach: h.level) + h.xp
        }
        self.init(tick: s.tick, blueGold: gold[0], redGold: gold[1], blueXP: xp[0], redXP: xp[1],
                  blueKills: s.teams[0].kills, redKills: s.teams[1].kills,
                  blueTowers: s.teams[0].towersDestroyed, redTowers: s.teams[1].towersDestroyed)
    }
}

/// 試合の年表。
public struct ReplayTimeline: Codable, Hashable, Sendable {
    /// サンプルの間隔（tick）。既定 10 秒。
    public static let defaultSampleInterval = 300

    /// tick 昇順（同 tick は発生順）。
    public var events: [TimelineEvent]
    /// tick 昇順。tick 0 と、以後 sampleInterval 毎。
    public var samples: [TimelineSample]
    public var sampleInterval: Int
    /// どの tick まで記録済みか（この tick までのイベント・サンプルは確定）。
    public var coveredTick: Int

    public init(events: [TimelineEvent] = [], samples: [TimelineSample] = [],
                sampleInterval: Int = ReplayTimeline.defaultSampleInterval, coveredTick: Int = 0) {
        self.events = events
        self.samples = samples
        self.sampleInterval = max(1, sampleInterval)
        self.coveredTick = coveredTick
    }

    /// tick より後の記録を捨てる（後退シーク）。
    public mutating func truncate(after tick: Int) {
        if let i = events.firstIndex(where: { $0.tick > tick }) { events.removeSubrange(i...) }
        if let i = samples.firstIndex(where: { $0.tick > tick }) { samples.removeSubrange(i...) }
        coveredTick = min(coveredTick, tick)
    }

    /// range 内のイベント（tick 昇順）。
    public func events(in range: ClosedRange<Int>) -> [TimelineEvent] {
        events.filter { range.contains($0.tick) }
    }

    /// tick 以前で最も新しいサンプル。
    public func sample(atOrBefore tick: Int) -> TimelineSample? {
        samples.last { $0.tick <= tick }
    }

    /// 次 / 前の重要な出来事（weight ≥ minWeight）。
    public func nextEvent(after tick: Int, minWeight: Double = 0) -> TimelineEvent? {
        events.first { $0.tick > tick && $0.weight >= minWeight }
    }

    public func previousEvent(before tick: Int, minWeight: Double = 0) -> TimelineEvent? {
        events.last { $0.tick < tick && $0.weight >= minWeight }
    }
}

/// 年表を作る（step 毎に observe を呼ぶ）。
public struct ReplayTimelineBuilder: Sendable {
    public private(set) var timeline: ReplayTimeline

    public init(sampleInterval: Int = ReplayTimeline.defaultSampleInterval) {
        timeline = ReplayTimeline(sampleInterval: sampleInterval)
    }

    public init(resuming timeline: ReplayTimeline) {
        self.timeline = timeline
    }

    /// 試合開始時（tick 0）の状態を記録する。
    public mutating func begin(state: SimState) {
        timeline.truncate(after: state.tick)
        if timeline.samples.last?.tick != state.tick { timeline.samples.append(TimelineSample(state: state)) }
        timeline.coveredTick = state.tick
    }

    /// 1 step の結果を取り込む（state は step 後）。既に記録済みの tick は無視する（同じ tick を二重に数えない）。
    public mutating func observe(events: [SimEvent], state s: SimState) {
        guard s.tick > timeline.coveredTick || (s.tick == 0 && timeline.samples.isEmpty) else {
            // 記録済みの tick は二重に数えない。例外は、同じ tick の step の後に来る試合終了
            // （リプレイが記録の最終 tick で中断終了する時など）。終了の印がまだ無ければ 1 回だけ取り込む。
            if s.tick == timeline.coveredTick { observeLateEnd(events: events, state: s) }
            return
        }
        for e in events {
            switch e {
            case .heroKilled(let k):
                let killerTeam = k.killerID.flatMap { s.unit($0)?.team }.flatMap { $0 == .neutral ? nil : $0 }
                timeline.events.append(TimelineEvent(
                    tick: s.tick,
                    kind: .kill(victimID: k.victimID, killerID: k.killerID, assistIDs: k.assistIDs, killerTeam: killerTeam,
                                isFirstBlood: k.isFirstBlood, multiKill: k.multiKill, isShutdown: k.isShutdown),
                    pos: s.unit(k.victimID)?.pos))
            case .structureDestroyed(let unitID, let kind, let team, let lane, let tier, let killerID):
                timeline.events.append(TimelineEvent(
                    tick: s.tick, kind: .structure(team: team, kind: kind, lane: lane, tier: tier, killerID: killerID),
                    pos: s.unit(unitID)?.pos))
            case .objectiveTaken(let kind, let team, let killerID):
                guard kind != .campLarge && kind != .campSmall else { continue }
                timeline.events.append(TimelineEvent(
                    tick: s.tick, kind: .objective(kind: kind, team: team, killerID: killerID),
                    pos: killerID.flatMap { s.unit($0)?.pos }))
            case .announcement(.ace(let team)):
                timeline.events.append(TimelineEvent(tick: s.tick, kind: .ace(team: team), pos: nil))
            case .matchEnded(let winner, let reason):
                timeline.events.append(TimelineEvent(tick: s.tick, kind: .matchEnd(winner: winner, reason: reason), pos: nil))
            default:
                break
            }
        }
        if s.tick % timeline.sampleInterval == 0 || s.phase == .ended {
            if timeline.samples.last?.tick != s.tick { timeline.samples.append(TimelineSample(state: s)) }
        }
        timeline.coveredTick = s.tick
    }

    /// 同じ tick に後から来た試合終了を取り込む（終了の印が無い時だけ）。
    private mutating func observeLateEnd(events: [SimEvent], state s: SimState) {
        guard s.phase == .ended else { return }
        let hasEnd = timeline.events.contains { if case .matchEnd = $0.kind { return true } else { return false } }
        guard !hasEnd else { return }
        for case .matchEnded(let winner, let reason) in events {
            timeline.events.append(TimelineEvent(tick: s.tick, kind: .matchEnd(winner: winner, reason: reason), pos: nil))
            if timeline.samples.last?.tick != s.tick { timeline.samples.append(TimelineSample(state: s)) }
            return
        }
    }

    /// tick より後を捨てて、そこから記録し直す（後退シーク）。
    public mutating func rewind(to tick: Int) {
        timeline.truncate(after: tick)
    }

    /// 別の年表で置き換える（バックグラウンドで先に作った年表を採用する時）。
    public mutating func replace(with other: ReplayTimeline) {
        timeline = other
    }
}
