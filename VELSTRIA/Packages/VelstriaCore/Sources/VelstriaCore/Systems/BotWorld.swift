import Foundation

// 担当: core-bots
// ボットが参照する 1 tick 分の世界の要約（ミニオンのレーン進行度・構造物・ヒーロー）と、レーン幾何のヘルパー。
// 意思決定する tick にだけ 1 回作る。列挙はすべて units の添字昇順（決定論）。

/// レーン経路上の位置（進行度 = 自陣 Core からの経路長）。
enum BotLane {
    /// レーン経路の全長（Blue / Red で同じ）。
    static func length(_ map: MapDefinition, _ lane: Lane) -> Double {
        let p = map.lanePaths[lane.rawValue]
        var total = 0.0
        for k in 1..<p.count { total += p[k - 1].distance(to: p[k]) }
        return total
    }

    /// Blue 視点の進行度と、レーン中心線までの距離。
    static func blueProgress(_ map: MapDefinition, _ lane: Lane, _ q: Vec2) -> (progress: Double, distance: Double) {
        let p = map.lanePaths[lane.rawValue]
        var bestD = Double.infinity
        var bestProgress = 0.0
        var acc = 0.0
        for k in 1..<p.count {
            let a = p[k - 1], b = p[k]
            let ab = b - a
            let len = ab.length
            let t = len < 1e-9 ? 0 : max(0, min(1, (q - a).dot(ab) / (len * len)))
            let d = q.distanceSquared(to: a + ab * t)
            if d < bestD {
                bestD = d
                bestProgress = acc + len * t
            }
            acc += len
        }
        return (bestProgress, bestD.squareRoot())
    }

    /// team 視点の進行度（自陣 Core = 0）。
    static func progress(_ map: MapDefinition, _ lane: Lane, team: Team, _ q: Vec2) -> Double {
        let bp = blueProgress(map, lane, q).progress
        return team == .red ? length(map, lane) - bp : bp
    }

    /// team 視点の進行度にあるレーン中心線上の点。
    static func point(_ map: MapDefinition, _ lane: Lane, team: Team, progress: Double) -> Vec2 {
        let p = map.lanePaths[lane.rawValue]
        let total = length(map, lane)
        var target = max(0, min(total, team == .red ? total - progress : progress))
        for k in 1..<p.count {
            let len = p[k - 1].distance(to: p[k])
            if target <= len || k == p.count - 1 {
                return len < 1e-9 ? p[k] : Vec2.lerp(p[k - 1], p[k], min(1, target / len))
            }
            target -= len
        }
        return p[p.count - 1]
    }

    /// 進行度 progress での team の前進方向（正規化）。
    static func forward(_ map: MapDefinition, _ lane: Lane, team: Team, progress: Double) -> Vec2 {
        let a = point(map, lane, team: team, progress: progress)
        let b = point(map, lane, team: team, progress: progress + 150)
        let d = (b - a).normalized
        return d == .zero ? (map.core(team.opponent) - map.core(team)).normalized : d
    }
}

/// ミニオンの要約。
struct BotMinionInfo {
    var index: Int
    var id: EntityID
    var team: Team
    var lane: Lane
    var type: MinionType
    var pos: Vec2
    /// Blue 視点の進行度。
    var blueProgress: Double
    var hp: Double
    var maxHP: Double
    var visibleMask: UInt8
    var targetID: EntityID?

    func progress(for team: Team, length: Double) -> Double { team == .red ? length - blueProgress : blueProgress }
    func isVisible(to team: Team) -> Bool { self.team == team || visibleMask & team.visionBit != 0 }
}

/// 構造物の要約（生存中のみ）。
struct BotStructureInfo {
    var index: Int
    var id: EntityID
    var team: Team
    var lane: Lane?
    var tier: TowerTier
    var isCore: Bool
    var pos: Vec2
    var radius: Double
    /// 攻撃が届く距離（射程 + 自身の半径。対象の半径は含まない）。
    var reach: Double
    var invulnerable: Bool
    var targetID: EntityID?
    var hp: Double
    var maxHP: Double
}

/// 1 tick 分の世界の要約。
struct BotWorld {
    var time: Double
    /// 全ヒーローの添字（昇順）。
    var heroes: [Int] = []
    var minions: [BotMinionInfo] = []
    var structures: [BotStructureInfo] = []
    /// 生存中の中立モンスターの添字。
    var monsters: [Int] = []
    /// レーン経路の全長（index = Lane.rawValue）。
    var laneLength: [Double]
    /// [team][lane] 味方ミニオンの最前線（自チーム視点の進行度、居なければ nil）。
    var front: [[Double?]] = [[nil, nil, nil], [nil, nil, nil]]
    /// [team][lane] 生存ミニオン数。
    var minionCount: [[Int]] = [[0, 0, 0], [0, 0, 0]]
    /// [team] 死亡中のヒーロー数（キルログ・スコアボードで誰でも知っている情報）。
    var deadHeroes: [Int] = [0, 0]
    var aliveHeroes: [Int] = [0, 0]

    init(_ s: SimState, _ ctx: SimContext) {
        time = s.time
        laneLength = Lane.allCases.map { BotLane.length(ctx.map, $0) }
        let invulnerable = WorldTargeting.structureInvulnerability(s)
        minions.reserveCapacity(96)
        for i in s.units.indices {
            guard s.units[i].isAlive else {
                if s.units[i].kind == .hero, s.units[i].team != .neutral { deadHeroes[s.units[i].team.rawValue] += 1 }
                if s.units[i].kind == .hero { heroes.append(i) }
                continue
            }
            switch s.units[i].kind {
            case .hero:
                heroes.append(i)
                let t = s.units[i].team
                if t != .neutral {
                    if s.units[i].hero?.isDead == true { deadHeroes[t.rawValue] += 1 } else { aliveHeroes[t.rawValue] += 1 }
                }
            case .minion:
                guard let m = s.units[i].minion, s.units[i].team != .neutral else { continue }
                let bp = BotLane.blueProgress(ctx.map, m.lane, s.units[i].pos).progress
                let info = BotMinionInfo(index: i, id: s.units[i].id, team: s.units[i].team, lane: m.lane, type: m.type,
                                         pos: s.units[i].pos, blueProgress: bp, hp: s.units[i].hp,
                                         maxHP: s.units[i].stats.maxHP, visibleMask: s.units[i].visibleMask,
                                         targetID: s.units[i].attackTargetID)
                minions.append(info)
                let tr = info.team.rawValue, lr = m.lane.rawValue
                let prog = info.progress(for: info.team, length: laneLength[lr])
                minionCount[tr][lr] += 1
                if let f = front[tr][lr] { front[tr][lr] = max(f, prog) } else { front[tr][lr] = prog }
            case .tower, .core:
                guard let td = s.units[i].tower else { continue }
                let u = s.units[i]
                structures.append(BotStructureInfo(index: i, id: u.id, team: u.team, lane: td.lane, tier: td.tier,
                                                   isCore: u.kind == .core, pos: u.pos, radius: u.radius,
                                                   reach: u.stats.attackRange + u.radius,
                                                   invulnerable: i < invulnerable.count && invulnerable[i],
                                                   targetID: u.attackTargetID, hp: u.hp, maxHP: u.stats.maxHP))
            case .monster:
                monsters.append(i)
            case .dummy:
                break
            }
        }
    }

    // MARK: - 構造物

    /// team の lane で最も前にある生存タワー（外 → 内 → 基部）。
    func frontTower(team: Team, lane: Lane) -> BotStructureInfo? {
        var best: BotStructureInfo?
        for st in structures where st.team == team && st.lane == lane && !st.isCore {
            if let b = best, b.tier.rawValue <= st.tier.rawValue { continue }
            best = st
        }
        return best
    }

    func core(of team: Team) -> BotStructureInfo? {
        structures.first { $0.team == team && $0.isCore }
    }

    /// team にとっての敵構造物のうち、p が攻撃範囲（+ margin）に入っているもの。
    func enemyStructure(covering p: Vec2, team: Team, margin: Double) -> BotStructureInfo? {
        for st in structures where st.team != team && st.team != .neutral {
            let r = st.reach + Balance.heroRadius + margin
            if st.pos.distanceSquared(to: p) <= r * r { return st }
        }
        return nil
    }

    /// team の味方構造物のうち、p を攻撃範囲（+ margin）に収めるもの。
    func alliedStructure(covering p: Vec2, team: Team, margin: Double) -> BotStructureInfo? {
        for st in structures where st.team == team {
            let r = st.reach + Balance.heroRadius + margin
            if st.pos.distanceSquared(to: p) <= r * r { return st }
        }
        return nil
    }

    /// 構造物の射程内にいる、team のミニオン数（盾になるミニオン）。
    func minionsUnder(_ st: BotStructureInfo, team: Team) -> Int {
        var n = 0
        for m in minions where m.team == team {
            let r = st.reach + 40
            if m.pos.distanceSquared(to: st.pos) <= r * r { n += 1 }
        }
        return n
    }

    /// team のヒーローが敵構造物 st の射程に入っても狙われないか（味方ミニオンが盾になっている）。
    func isTowerTanked(_ st: BotStructureInfo, by team: Team, heroIDs: [EntityID]) -> Bool {
        if let tid = st.targetID, heroIDs.contains(tid) { return false }
        return minionsUnder(st, team: team) >= 2
    }

    /// team 視点で lane の敵ミニオンの最前線（視認できるもののみ、自チーム視点の進行度）。
    func visibleEnemyFront(team: Team, lane: Lane) -> (progress: Double, count: Int)? {
        var best: Double?
        var n = 0
        let len = laneLength[lane.rawValue]
        for m in minions where m.lane == lane && m.team != team && m.isVisible(to: team) {
            let p = m.progress(for: team, length: len)
            n += 1
            if let b = best, b <= p { continue }
            best = p
        }
        guard let b = best else { return nil }
        return (b, n)
    }
}
