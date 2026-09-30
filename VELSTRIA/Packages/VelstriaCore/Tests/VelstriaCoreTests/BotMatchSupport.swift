import XCTest
@testable import VelstriaCore

/// ボット戦の集計（BotMatchTests / BotPerformanceTests 共通）。
struct BotMatchReport {
    struct Hero {
        var id: EntityID
        var heroID: String
        var team: Team
        var position: LanePosition
        var isBot: Bool
        var levelAt12: Int = 0
        var itemsAt12: Int = 0
        var finalLevel = 0
        var finalItems = 0
        var kills = 0
        var deaths = 0
        var cs = 0
        /// 生存中の移動距離（転移・復活の瞬間移動を除く）と生存 tick 数。
        var moved: Double = 0
        var aliveTicks = 0

        var movedPerMinute: Double { aliveTicks > 0 ? moved / (Double(aliveTicks) * Balance.dt / 60) : 0 }
    }

    var label: String
    var duration: Double = 0
    var winner: Team?
    var endReason: EndReason?
    var kills: [Int] = [0, 0]
    /// 処刑（塔・ミニオン・泉のみで倒れた）の数。
    var executions = 0
    var towers: [Int] = [0, 0]
    var wyrms: [Int] = [0, 0]
    var colossi: [Int] = [0, 0]
    var heroes: [Hero] = []
    var finalHash: UInt64 = 0
    var eventCount = 0
    var ticks = 0
    var decisions = 0
    var msPerTick: Double = 0
    var timeline: [String] = []

    func avgLevelAt12(_ team: Team) -> Double {
        let hs = heroes.filter { $0.team == team && $0.isBot }
        return hs.isEmpty ? 0 : Double(hs.map(\.levelAt12).reduce(0, +)) / Double(hs.count)
    }

    var avgLevelAt12: Double {
        let hs = heroes.filter(\.isBot)
        return hs.isEmpty ? 0 : Double(hs.map(\.levelAt12).reduce(0, +)) / Double(hs.count)
    }

    var itemsPerHero: Double {
        let hs = heroes.filter(\.isBot)
        return hs.isEmpty ? 0 : Double(hs.map(\.finalItems).reduce(0, +)) / Double(hs.count)
    }

    static func tableHeader() -> String {
        "| match | duration | winner | kills B/R (exec) | towers B/R | wyrm B/R | colossus B/R | avg Lv @12:00 | items/hero @12:00 | items/hero end | ms/tick |\n"
            + "|---|---|---|---|---|---|---|---|---|---|---|"
    }

    var tableRow: String {
        let bots = heroes.filter(\.isBot)
        let items12 = bots.isEmpty ? 0 : Double(bots.map(\.itemsAt12).reduce(0, +)) / Double(bots.count)
        let m = Int(duration) / 60, sec = Int(duration) % 60
        return String(format: "| %@ | %d:%02d | %@ | %d / %d (%d) | %d / %d | %d / %d | %d / %d | %.1f | %.1f | %.1f | %.3f |",
                      label, m, sec, winner.map { "\($0)" } ?? "-", kills[0], kills[1], executions, towers[0], towers[1],
                      wyrms[0], wyrms[1], colossi[0], colossi[1], avgLevelAt12, items12, itemsPerHero, msPerTick)
    }

    /// 試合を最後まで回して集計する。humanCommands は人間の入力（nil = 何もしない）。
    static func run(_ label: String, config: MatchConfig, maxTime: Double = 40 * 60,
                    keepTimeline: Bool = false) -> BotMatchReport {
        let sim = Simulation(config: config)
        var r = BotMatchReport(label: label)
        for i in sim.state.heroIndices {
            let u = sim.state.units[i]
            r.heroes.append(Hero(id: u.id, heroID: u.hero!.heroID, team: u.team, position: u.hero!.position,
                                 isBot: u.hero!.controller == .bot))
        }
        var slot: [EntityID: Int] = [:]
        for (k, h) in r.heroes.enumerated() { slot[h.id] = k }
        var last = sim.state.heroIndices.map { sim.state.units[$0].pos }
        let heroIdx = sim.state.heroIndices
        let t0 = DispatchTime.now().uptimeNanoseconds
        while !sim.isEnded && sim.state.time < maxTime {
            let events = sim.step()
            r.eventCount += events.count
            for e in events {
                switch e {
                case .heroKilled(let k):
                    // 処刑（敵ヒーローの関与なし）はチームのキルに数えない（SimState.teams と同じ基準）
                    if let v = slot[k.victimID] {
                        r.heroes[v].deaths += 1
                        if k.killerID != nil { r.kills[r.heroes[v].team.opponent.rawValue] += 1 } else { r.executions += 1 }
                    }
                    if let killer = k.killerID, let kk = slot[killer] { r.heroes[kk].kills += 1 }
                    if keepTimeline {
                        r.timeline.append(String(format: "%5.0fs kill %@ -> %@", sim.state.time,
                                                 k.killerID.flatMap { slot[$0] }.map { r.heroes[$0].heroID } ?? "-",
                                                 slot[k.victimID].map { r.heroes[$0].heroID } ?? "?"))
                    }
                case .structureDestroyed(_, let kind, let team, let lane, let tier, _):
                    if team != .neutral { r.towers[team.opponent.rawValue] += 1 }
                    if keepTimeline {
                        r.timeline.append(String(format: "%5.0fs %@ %@ %@ %@ destroyed", sim.state.time, "\(team)",
                                                 "\(kind)", lane.map { "\($0)" } ?? "-", tier.map { "\($0)" } ?? "-"))
                    }
                case .objectiveTaken(let kind, let team, _):
                    guard team != .neutral else { break }
                    if kind == .astralWyrm { r.wyrms[team.rawValue] += 1 }
                    if kind == .ancientColossus { r.colossi[team.rawValue] += 1 }
                    if keepTimeline { r.timeline.append(String(format: "%5.0fs %@ takes %@", sim.state.time, "\(team)", "\(kind)")) }
                default:
                    break
                }
            }
            for (k, i) in heroIdx.enumerated() {
                let u = sim.state.units[i]
                let alive = u.isAlive && u.hero?.isDead == false
                let d = u.pos.distance(to: last[k])
                if alive {
                    r.heroes[k].aliveTicks += 1
                    // 復活・帰還の瞬間移動は除く
                    if d < 120 { r.heroes[k].moved += d }
                }
                last[k] = u.pos
            }
            if sim.state.tick == 12 * 60 * 30 {
                for (k, i) in heroIdx.enumerated() {
                    r.heroes[k].levelAt12 = sim.state.units[i].hero!.level
                    r.heroes[k].itemsAt12 = sim.state.units[i].hero!.items.count
                }
            }
        }
        r.msPerTick = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 / Double(max(1, sim.state.tick))
        r.duration = sim.state.time
        r.winner = sim.state.winner
        r.endReason = sim.state.endReason
        r.ticks = sim.state.tick
        r.decisions = sim.state.bots.decisions
        r.finalHash = sim.state.stateHash()
        for (k, i) in heroIdx.enumerated() {
            let h = sim.state.units[i].hero!
            r.heroes[k].finalLevel = h.level
            r.heroes[k].finalItems = h.items.count
            r.heroes[k].cs = h.score.creepScore
            if sim.state.tick < 12 * 60 * 30 {
                r.heroes[k].levelAt12 = h.level
                r.heroes[k].itemsAt12 = h.items.count
            }
        }
        return r
    }

    /// ヒーロー毎の詳細（失敗時の調査用）。
    var heroLines: [String] {
        heroes.map {
            String(format: "  %@ %@ %@ %@ Lv%d(@12:%d) items %d(@12:%d) K/D %d/%d CS %d move %.0f/min",
                   "\($0.team)", $0.heroID, "\($0.position)", $0.isBot ? "bot" : "human", $0.finalLevel, $0.levelAt12,
                   $0.finalItems, $0.itemsAt12, $0.kills, $0.deaths, $0.cs, $0.movedPerMinute)
        }
    }
}
