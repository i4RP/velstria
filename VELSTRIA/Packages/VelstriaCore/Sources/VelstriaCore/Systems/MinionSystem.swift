import Foundation

// 担当: core-world。ミニオンの索敵優先度・救援要請・追跡制限・レーン進行・巨像の加護による強化（DESIGN §3・§4）。
// 移動そのもの（経路追従・押し合い）は MovementSystem、攻撃（前隙・射程外の追跡）は CombatSystem が行う。

public enum MinionSystem {
    /// 救援要請: 味方ヒーロー（victim）を直近に攻撃した敵ヒーロー（aggressor）。
    struct HelpCall {
        var aggressor: Int
        var victimPos: Vec2
    }

    /// 経由点を「通過した」とみなす、区間終点手前の距離。
    static let waypointPassTolerance: Double = 100
    /// 経由点にこの距離まで近づけば通過扱い。
    static let waypointReachRadius: Double = 150
    /// レーン復帰時に目指す、最寄り点からの前方距離。
    static let returnLookAhead: Double = 200
    /// 縦列の重なりを減らす横ずれ量。
    static let laneLateralSpread: Double = 40

    /// 1 tick 分の共有データ（索敵候補・構造物の無敵・レーン経路・救援要請）。
    struct Frame {
        var candidates: [WorldCandidate]
        var grid: WorldSpatialIndex
        /// units の添字 → candidates の添字（-1 = 候補外）。
        var slot: [Int]
        var invulnerable: [Bool]
        /// [Team.rawValue][Lane.rawValue] のチーム視点の経路。
        var paths: [[[Vec2]]]
        var calls: [[HelpCall]]

        func isInvulnerable(_ i: Int) -> Bool { i < invulnerable.count && invulnerable[i] }

        func candidate(forUnit i: Int?) -> WorldCandidate? {
            guard let i, i >= 0, i < slot.count, slot[i] >= 0 else { return nil }
            return candidates[slot[i]]
        }
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let blessed = blessedHeroPositions(s)
        let candidates = WorldTargeting.candidates(s)
        var slot = [Int](repeating: -1, count: s.units.count)
        for (k, c) in candidates.enumerated() { slot[c.index] = k }
        let frame = Frame(candidates: candidates, grid: WorldSpatialIndex(candidates), slot: slot,
                          invulnerable: WorldTargeting.structureInvulnerability(s),
                          paths: Team.players.map { team in Lane.allCases.map { ctx.map.lanePath($0, for: team) } },
                          calls: helpCalls(s))
        for i in s.units.indices where s.units[i].kind == .minion && s.units[i].isAlive {
            updateEmpowerment(&s, ctx, i, blessed: blessed)
            think(&s, ctx, i, frame: frame)
        }
    }

    // MARK: - 行動決定

    static func think(_ s: inout SimState, _ ctx: SimContext, _ i: Int, frame: Frame) {
        let team = s.units[i].team
        guard team == .blue || team == .red, var m = s.units[i].minion else { return }
        let path = frame.paths[team.rawValue][m.lane.rawValue]
        guard path.count >= 2 else { return }
        let pos = s.units[i].pos
        advanceWaypoint(&m, pos: pos, path: path)
        s.units[i].minion = m
        let myLaneDist = MapDefinition.project(pos, onto: path).distance
        let onLeash = myLaneDist <= Balance.minionLaneChaseLimit
        let currentID = s.units[i].attackTargetID
        let current = frame.candidate(forUnit: s.index(of: currentID))

        // 1) 救援要請（味方ヒーローを攻撃した敵ヒーロー）: 現在の対象がヒーローでなければ切り替える
        if onLeash, let a = callForHelpTarget(s, i, frame: frame, path: path) {
            let keepHero = current.map { $0.kind == .hero && canKeep(s, i, $0, path: path, frame: frame) } ?? false
            if !keepHero {
                if current?.index != a { setTarget(&s, i, a) }
                return
            }
        }

        // 2) 現在の対象を維持（死亡・範囲外・レーンから離れすぎで解除）
        if let c = current, onLeash, canKeep(s, i, c, path: path, frame: frame) { return }
        if currentID != nil { clearTarget(&s, i) }

        // 3) 新しい対象（レーンから外れて戻る途中は射程内の敵にだけ反撃する）
        if onLeash {
            let returning = myLaneDist > Balance.minionReturnThreshold
            let radius = returning ? s.units[i].stats.attackRange + s.units[i].radius : Balance.minionAcquireRadius
            if let t = acquire(s, i, radius: radius, path: path, frame: frame) {
                setTarget(&s, i, t)
                return
            }
        }

        // 4) レーンを進む（レーンから外れていれば壁を避けて合流点へ）
        var goal = laneGoal(id: s.units[i].id, pos: pos, m, path: path, laneDistance: myLaneDist)
        if myLaneDist > Balance.minionReturnThreshold {
            goal = WorldSteering.nextWaypoint(ctx, from: pos, to: goal, radius: s.units[i].radius)
        }
        s.units[i].moveIntent = .point(goal)
    }

    static func setTarget(_ s: inout SimState, _ i: Int, _ t: Int) {
        let id = s.units[t].id
        s.units[i].attackTargetID = id
        s.units[i].windupRemaining = nil
        s.units[i].moveIntent = .follow(targetID: id, range: s.units[i].stats.attackRange)
        s.units[i].path = []
    }

    static func clearTarget(_ s: inout SimState, _ i: Int) {
        s.units[i].attackTargetID = nil
        s.units[i].windupRemaining = nil
        if case .follow = s.units[i].moveIntent { s.units[i].moveIntent = .none }
    }

    /// ミニオンが攻撃しうる種別か（中立モンスターは無視）。
    static func isAttackableKind(_ kind: UnitKind, team: Team) -> Bool {
        switch kind {
        case .minion, .hero, .tower, .core, .dummy: return team != .neutral
        case .monster: return false
        }
    }

    /// 対象を維持できるか（生存・可視・維持半径内・対象がレーンから離れすぎていない・無敵構造物でない）。
    static func canKeep(_ s: SimState, _ i: Int, _ c: WorldCandidate, path: [Vec2], frame: Frame) -> Bool {
        let team = s.units[i].team
        guard isAttackableKind(c.kind, team: c.team), c.isTargetableEnemy(of: team) else { return false }
        let keep = Balance.minionKeepRadius + c.radius
        guard s.units[i].pos.distanceSquared(to: c.pos) <= keep * keep else { return false }
        if c.isStructure { return !frame.isInvulnerable(c.index) }
        return MapDefinition.project(c.pos, onto: path).distance <= Balance.minionLaneChaseLimit
    }

    /// 優先: 最も近い敵ミニオン > 最も近い敵構造物/人形 > 最も近い敵ヒーロー（すべて radius 以内）。
    static func acquire(_ s: SimState, _ i: Int, radius: Double, path: [Vec2], frame: Frame) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        var best: [Int] = [-1, -1, -1]
        var bestD: [Double] = [.infinity, .infinity, .infinity]
        frame.grid.forEach(near: pos, radius: radius) { k in
            let c = frame.candidates[k]
            guard c.team != team, isAttackableKind(c.kind, team: c.team) else { return }
            let r = radius + c.radius
            let d = pos.distanceSquared(to: c.pos)
            guard d <= r * r, c.isVisible(to: team) else { return }
            let tier: Int
            switch c.kind {
            case .minion: tier = 0
            case .tower, .core, .dummy: tier = 1
            default: tier = 2
            }
            // 同距離は添字の小さい方（格子の訪問順に依存しない）
            guard d < bestD[tier] || (d == bestD[tier] && c.index < best[tier]) else { return }
            if c.isStructure {
                if frame.isInvulnerable(c.index) { return }
            } else if MapDefinition.project(c.pos, onto: path).distance > Balance.minionLaneChaseLimit {
                return
            }
            bestD[tier] = d
            best[tier] = c.index
        }
        for t in best where t >= 0 { return t }
        return nil
    }

    /// 味方ヒーローを攻撃した敵ヒーローのうち、このミニオンの索敵半径内で最も近いもの。
    static func callForHelpTarget(_ s: SimState, _ i: Int, frame: Frame, path: [Vec2]) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        var best: Int?
        var bestD = Double.infinity
        for c in frame.calls[team.rawValue] {
            let helpR = Balance.callForHelpRadius
            guard c.victimPos.distanceSquared(to: pos) <= helpR * helpR else { continue }
            let a = c.aggressor
            let r = Balance.minionAcquireRadius + s.units[a].radius
            let d = s.units[a].pos.distanceSquared(to: pos)
            guard d <= r * r, s.units[a].visibleMask & team.visionBit != 0 else { continue }
            guard MapDefinition.project(s.units[a].pos, onto: path).distance <= Balance.minionLaneChaseLimit else { continue }
            if d < bestD || (d == bestD && a < (best ?? Int.max)) {
                bestD = d
                best = a
            }
        }
        return best
    }

    /// チーム別の救援要請一覧（index = Team.rawValue、blue/red）。
    static func helpCalls(_ s: SimState) -> [[HelpCall]] {
        var out: [[HelpCall]] = [[], []]
        let since = s.time - Balance.callForHelpWindow
        for v in s.units.indices where s.units[v].kind == .hero && s.units[v].isAlive {
            let team = s.units[v].team
            guard team == .blue || team == .red, s.units[v].hero?.isDead != true else { continue }
            var ids: [EntityID] = []
            if s.units[v].lastDamagedTime >= since, let a = s.units[v].lastAttackerID { ids.append(a) }
            for rec in s.units[v].hero?.recentDamagers ?? [] where rec.time >= since && !ids.contains(rec.sourceID) {
                ids.append(rec.sourceID)
            }
            for id in ids {
                guard let a = s.index(of: id), s.units[a].kind == .hero, s.units[a].team == team.opponent,
                      s.units[a].isAlive, s.units[a].hero?.isDead != true else { continue }
                out[team.rawValue].append(HelpCall(aggressor: a, victimPos: s.units[v].pos))
            }
        }
        return out
    }

    // MARK: - レーン進行

    /// 射影で経由点の通過を判定して進める（押し出されて先に進んだ場合も連続して進める）。
    static func advanceWaypoint(_ m: inout MinionData, pos: Vec2, path: [Vec2]) {
        m.waypointIndex = min(max(1, m.waypointIndex), path.count - 1)
        while m.waypointIndex < path.count - 1 {
            let a = path[m.waypointIndex - 1], b = path[m.waypointIndex]
            let ab = b - a
            let len = ab.length
            let along = len > 1e-9 ? (pos - a).dot(ab) / len : len
            if along >= len - waypointPassTolerance || pos.distanceSquared(to: b) < waypointReachRadius * waypointReachRadius {
                m.waypointIndex += 1
            } else {
                break
            }
        }
    }

    /// 次に向かう地点。レーンから離れていれば現在区間の最寄り点の少し先へ戻る。
    static func laneGoal(id: EntityID, pos: Vec2, _ m: MinionData, path: [Vec2], laneDistance: Double) -> Vec2 {
        let k = min(max(1, m.waypointIndex), path.count - 1)
        if laneDistance > Balance.minionReturnThreshold {
            let proj = MapDefinition.project(pos, onto: path, firstSegmentEnd: k)
            let a = path[proj.segmentEnd - 1], b = path[proj.segmentEnd]
            let dir = (b - a).normalized
            return proj.point + dir * min(returnLookAhead, proj.point.distance(to: b))
        }
        let dir = (path[k] - path[k - 1]).normalized
        let lateral = Double(Int(id % 3) - 1) * laneLateralSpread
        return path[k] + dir.perpendicular * lateral
    }

    // MARK: - 巨像の加護

    /// 巨像の加護を持つ生存ヒーローの位置（index = Team.rawValue、blue/red）。
    static func blessedHeroPositions(_ s: SimState) -> [[Vec2]] {
        var out: [[Vec2]] = [[], []]
        for i in s.units.indices where s.units[i].kind == .hero && s.units[i].isAlive {
            let team = s.units[i].team
            guard team == .blue || team == .red, s.units[i].hero?.isDead != true,
                  s.units[i].statuses.contains(where: { $0.kind == .colossusBlessing }) else { continue }
            out[team.rawValue].append(s.units[i].pos)
        }
        return out
    }

    /// 加護を持つ味方ヒーローの近くでは HP・攻撃 ×1.5（baseStats を 1 度だけ拡大し、離れたら戻す）。
    static func updateEmpowerment(_ s: inout SimState, _ ctx: SimContext, _ i: Int, blessed: [[Vec2]]) {
        guard let m = s.units[i].minion, s.units[i].team == .blue || s.units[i].team == .red else { return }
        let sources = blessed[s.units[i].team.rawValue]
        let pos = s.units[i].pos
        let k = Balance.minionEmpowerMultiplier
        if !m.empowered {
            let r = Balance.minionEmpowerRadius
            guard sources.contains(where: { $0.distanceSquared(to: pos) <= r * r }) else { return }
            s.units[i].baseStats.maxHP *= k
            s.units[i].baseStats.attack *= k
            s.units[i].minion?.empowered = true
        } else {
            let r = Balance.minionEmpowerReleaseRadius
            guard !sources.contains(where: { $0.distanceSquared(to: pos) <= r * r }) else { return }
            s.units[i].baseStats.maxHP /= k
            s.units[i].baseStats.attack /= k
            s.units[i].minion?.empowered = false
        }
        // 最大 HP の変化は StatCalculator が現在 HP の割合を保って反映する
        StatCalculator.recompute(&s, i, ctx)
    }
}
