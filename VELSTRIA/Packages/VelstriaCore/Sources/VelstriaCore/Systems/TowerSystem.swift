import Foundation

// 担当: core-world。構造物（タワー / Core）の索敵・連続命中・ダメージ補正・無敵判定（DESIGN §3・§4）。
// 構造物は移動しない。攻撃の前隙・発射は CombatSystem、1 発のダメージ量は attackDamage が決める。

public enum TowerSystem {
    /// 外塔のエネルギーシールドの識別子（`Shield.tag`）。
    public static let shieldTag = "outerTowerShield"

    /// 外塔のシールドが残っているか。
    public static func hasTurretShield(_ u: Unit) -> Bool {
        u.shields.contains { $0.tag == shieldTag && $0.amount > 0 && $0.remaining > 0 }
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let candidates = WorldTargeting.candidates(s)
        let grid = WorldSpatialIndex(candidates)
        for i in s.units.indices where s.units[i].isStructure && s.units[i].isAlive {
            let pick = chooseTarget(s, towerIndex: i, candidates: candidates, grid: grid)
            let newID = pick.map { s.units[$0].id }
            if newID != s.units[i].attackTargetID {
                s.units[i].attackTargetID = newID
                // ターゲット変更: 前隙を取り消して新しい対象へ撃ち直し、連続命中ボーナスをリセット
                s.units[i].windupRemaining = nil
                s.units[i].tower?.rampTargetID = nil
                s.units[i].tower?.rampHits = 0
            }
            if let t = pick {
                s.units[i].facing = (s.units[t].pos - s.units[i].pos).angle
            }
        }
    }

    // MARK: - 索敵

    /// 優先: 射程内で「味方ヒーローを直近 2 秒に攻撃した敵ヒーロー」> 現在の対象（射程内なら維持）
    ///       > 最も近いミニオン > 最も近いヒーロー（練習用人形はヒーロー扱い）。
    static func chooseTarget(_ s: SimState, towerIndex i: Int, candidates: [WorldCandidate],
                             grid: WorldSpatialIndex) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        let reachBase = s.units[i].stats.attackRange + s.units[i].radius
        let currentID = s.units[i].attackTargetID
        let since = s.time - Balance.towerAggroWindow
        var aggressorIDs: [EntityID] = []
        // 射程内の敵（添字昇順に並べ直して同点処理を決定論的にする）
        var enemies: [Int] = []
        grid.forEach(near: pos, radius: reachBase) { k in
            let c = candidates[k]
            let reach = reachBase + c.radius
            guard c.pos.distanceSquared(to: pos) <= reach * reach else { return }
            if c.team == team {
                // 射程内の味方ヒーローを最近攻撃した者
                guard c.kind == .hero else { return }
                if s.units[c.index].lastDamagedTime >= since, let a = s.units[c.index].lastAttackerID {
                    aggressorIDs.append(a)
                }
                for rec in s.units[c.index].hero?.recentDamagers ?? [] where rec.time >= since {
                    aggressorIDs.append(rec.sourceID)
                }
                return
            }
            guard c.team != .neutral, c.kind == .minion || c.kind == .hero || c.kind == .dummy,
                  c.isVisible(to: team) else { return }
            enemies.append(k)
        }
        enemies.sort()
        var current: Int?
        var bestMinion: Int?, bestHero: Int?, bestAggressor: Int?
        var dMinion = Double.infinity, dHero = Double.infinity, dAggressor = Double.infinity
        var currentIsAggressor = false
        for k in enemies {
            let c = candidates[k]
            let d = c.pos.distanceSquared(to: pos)
            if c.id == currentID { current = c.index }
            if c.kind == .minion {
                if d < dMinion { dMinion = d; bestMinion = c.index }
                continue
            }
            if d < dHero { dHero = d; bestHero = c.index }
            if c.kind == .hero && aggressorIDs.contains(c.id) {
                if c.id == currentID { currentIsAggressor = true }
                if d < dAggressor { dAggressor = d; bestAggressor = c.index }
            }
        }
        if currentIsAggressor { return current }
        return bestAggressor ?? current ?? bestMinion ?? bestHero
    }

    /// 構造物の攻撃が届く距離か（射程 + 双方の半径。CombatSystem と同じ基準）。
    static func inReach(_ tower: Unit, _ v: Unit) -> Bool {
        let reach = tower.stats.attackRange + tower.radius + v.radius
        return tower.pos.distanceSquared(to: v.pos) <= reach * reach
    }

    // MARK: - ダメージ

    /// 構造物（タワー/Core）の通常攻撃 1 発のダメージ（対ミニオンは最大 HP 割合、対ヒーローは連続命中補正込み）。
    /// CombatSystem が構造物の攻撃命中時に呼ぶ。対ミニオンの値は確定ダメージとして適用される前提。
    public static func attackDamage(_ s: inout SimState, _ ctx: SimContext, towerIndex i: Int, targetIndex t: Int) -> Double {
        let tower = s.units[i]
        let target = s.units[t]
        switch target.kind {
        case .minion:
            s.units[i].tower?.rampTargetID = target.id
            s.units[i].tower?.rampHits = 0
            let pct: Double
            switch target.minion?.type ?? .melee {
            case .melee: pct = Balance.towerMeleeMinionDamagePct
            case .ranged: pct = Balance.towerRangedMinionDamagePct
            case .siege: pct = Balance.towerSiegeMinionDamagePct
            }
            // CombatSystem は構造物 → ミニオンの弾を確定ダメージ（防御無視）として適用する。
            // 最終的に最大 HP の pct だけ削れるよう、その際に掛かる与ダメ補正と被ダメ軽減（DESIGN §5 の 3・5）を
            // あらかじめ打ち消しておく
            let bonus = max(0.05, 1 + tower.stats.damageBonus)
            let reduction = max(0.05, 1 - min(Balance.maxDamageReduction, max(0, target.stats.damageReduction)))
            return pct * target.stats.maxHP / (bonus * reduction)
        case .hero, .dummy:
            var hits = 0
            if tower.tower?.rampTargetID == target.id { hits = tower.tower?.rampHits ?? 0 }
            let ramp = min(Balance.towerRampMax, Balance.towerRampPerHit * Double(hits))
            s.units[i].tower?.rampTargetID = target.id
            s.units[i].tower?.rampHits = hits + 1
            return tower.stats.attack * (1 + ramp)
        default:
            return tower.stats.attack
        }
    }

    /// 構造物が受けるダメージの倍率（序盤保護・裏取り保護・攻城ミニオン ×1.5 など）。CombatSystem.applyDamage が呼ぶ。
    public static func damageTakenMultiplier(_ s: SimState, _ ctx: SimContext, structureIndex i: Int,
                                             sourceIndex: Int?) -> Double {
        guard i >= 0, i < s.units.count, s.units[i].isStructure else { return 1 }
        var m = 1.0
        // 序盤保護: 外塔はエネルギーシールドがある間（開始〜5:00）被ダメ −30%（攻撃者を問わない）
        if s.units[i].kind == .tower, s.units[i].tower?.tier == .outer, hasTurretShield(s.units[i]) {
            m *= 1 - Balance.outerTowerShieldReduction
        }
        guard let a = sourceIndex, a >= 0, a < s.units.count else { return m }
        switch s.units[a].kind {
        case .hero:
            // 裏取り保護: 攻撃側のミニオンが構造物の近くに居なければヒーローからのダメージ −50%
            let team = s.units[i].team
            let pos = s.units[i].pos
            var escorted = false
            for k in s.units.indices where s.units[k].kind == .minion && s.units[k].isAlive {
                let t = s.units[k].team
                guard t != team, t != .neutral else { continue }
                let r = Balance.backdoorMinionRadius + s.units[k].radius
                if s.units[k].pos.distanceSquared(to: pos) <= r * r { escorted = true; break }
            }
            if !escorted { m *= 1 - Balance.backdoorReduction }
        case .minion:
            if s.units[a].minion?.type == .siege { m *= Balance.siegeStructureDamageMultiplier }
        default:
            break
        }
        return m
    }

    // MARK: - 無敵判定

    /// 構造物が現在無敵か（同レーンの前段タワー生存中 / Core は基部塔が 1 本も落ちていない間）。
    public static func isInvulnerable(_ s: SimState, _ ctx: SimContext, index i: Int) -> Bool {
        guard i >= 0, i < s.units.count, s.units[i].isStructure, let td = s.units[i].tower else { return false }
        let team = s.units[i].team
        if s.units[i].kind == .core {
            for k in s.units.indices where s.units[k].kind == .tower && s.units[k].team == team && !s.units[k].isAlive {
                if s.units[k].tower?.tier == .base { return false }
            }
            return true
        }
        for k in s.units.indices where s.units[k].kind == .tower && s.units[k].team == team && s.units[k].isAlive {
            guard let other = s.units[k].tower else { continue }
            if other.lane == td.lane && other.tier.rawValue < td.tier.rawValue { return true }
        }
        return false
    }
}
