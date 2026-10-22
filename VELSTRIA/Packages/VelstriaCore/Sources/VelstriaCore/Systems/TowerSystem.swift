import Foundation

// 担当: core-world。構造物（塔 / ベース）の索敵・連続命中・ダメージ補正・無敵判定・保護（DESIGN §3・§4）。
// 数値と規則は MLBB 本サーバー 2.2.16（Balance.Tower、docs/TOWER_BASE_MLBB.md）。
// 構造物は移動しない。攻撃の前隙・発射は CombatSystem、1 発のダメージ量は attackDamage が決める（確定ダメージ）。
// 凍結（キット層の Kit.freezeStructure）の間は索敵せず、CombatSystem も攻撃しない（行動不能の状態は canAct で見る）。

public enum TowerSystem {
    /// 外塔のエネルギーシールドの識別子（`Shield.tag`）。
    public static let shieldTag = "outerTowerShield"

    /// 外塔のシールドが残っているか。
    public static func hasTurretShield(_ u: Unit) -> Bool {
        u.shields.contains { $0.tag == shieldTag && $0.amount > 0 && $0.remaining > 0 }
    }

    /// アウタータワーがまだ眠っているか（最初のミニオンが出てから 15 秒は攻撃せず、無敵）。
    static func isAsleep(_ s: SimState, index i: Int) -> Bool {
        s.units[i].kind == .tower && s.units[i].tower?.tier == .outer && s.time < Balance.Tower.outerWakeTime
    }

    /// 召喚されたロード（倒されて味方として出撃した古環の巨像）か。MLBB: 味方のヒーローとして扱われ、塔はミニオンより先に狙う。
    public static func isSummonedLord(_ u: Unit) -> Bool {
        u.kind == .monster && u.team != .neutral && u.monster?.kind == .ancientColossus
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let candidates = WorldTargeting.candidates(s)
        let grid = WorldSpatialIndex(candidates)
        for i in s.units.indices where s.units[i].isStructure && s.units[i].isAlive {
            if s.units[i].kind == .core { regenerate(&s, i) }
            if s.units[i].tower?.holyDefenseArmed == true { holyDefense(&s, ctx, i, candidates: candidates, grid: grid) }
            // 凍結（行動不能。オーリアの凍結だけが構造物に付く）の間は索敵も向きの変更もしない。
            // 攻撃の前隙・発射は CombatSystem.stepAttacker が canAct で止める
            guard s.units[i].canAct else { continue }
            if isAsleep(s, index: i) {
                s.units[i].attackTargetID = nil
                s.units[i].windupRemaining = nil
                continue
            }
            let pick = chooseTarget(s, towerIndex: i, candidates: candidates, grid: grid)
            let newID = pick.map { s.units[$0].id }
            if newID != s.units[i].attackTargetID {
                // ターゲット変更: 前隙を取り消して新しい対象へ撃ち直す。連続命中は 2 秒以内に同じヒーローへ戻れば続く（attackDamage）
                s.units[i].attackTargetID = newID
                s.units[i].windupRemaining = nil
            }
            if let t = pick {
                s.units[i].facing = (s.units[t].pos - s.units[i].pos).angle
            }
        }
    }

    // MARK: - 索敵

    /// MLBB の狙う順:
    /// 1. 今の対象がヒーロー（練習用人形を含む）で射程内なら撃ち続ける（ほかの敵ヒーローが味方を攻撃しても替えない）。
    /// 2. 射程内で「味方ヒーロー（射程より少し外まで）を直近 2 秒に攻撃した敵ヒーロー」。
    /// 3. 召喚されたロード（ミニオンの中で最優先）。
    /// 4. 今の対象（射程に最初に入った敵を、死ぬ・射程を出るまで撃つ）。
    /// 5. 最も近いミニオン > 最も近いヒーロー。
    static func chooseTarget(_ s: SimState, towerIndex i: Int, candidates: [WorldCandidate],
                             grid: WorldSpatialIndex) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        let reachBase = s.units[i].stats.attackRange + s.units[i].radius
        let allyReach = reachBase + Balance.towerAggroAllyMargin
        let currentID = s.units[i].attackTargetID
        let since = s.time - Balance.towerAggroWindow
        var aggressorIDs: [EntityID] = []
        // 射程内の敵（添字昇順に並べ直して同点処理を決定論的にする）
        var enemies: [Int] = []
        grid.forEach(near: pos, radius: allyReach) { k in
            let c = candidates[k]
            let d2 = c.pos.distanceSquared(to: pos)
            if c.team == team {
                // 射程より少し外までの味方ヒーローを最近攻撃した者
                guard c.kind == .hero else { return }
                let r = allyReach + c.radius
                guard d2 <= r * r else { return }
                if s.units[c.index].lastDamagedTime >= since, let a = s.units[c.index].lastAttackerID {
                    aggressorIDs.append(a)
                }
                for rec in s.units[c.index].hero?.recentDamagers ?? [] where rec.time >= since {
                    aggressorIDs.append(rec.sourceID)
                }
                return
            }
            let reach = reachBase + c.radius
            guard d2 <= reach * reach, c.team != .neutral, c.isVisible(to: team) else { return }
            switch c.kind {
            case .minion, .hero, .dummy:
                enemies.append(k)
            case .monster where isSummonedLord(s.units[c.index]):
                enemies.append(k)
            default:
                return
            }
        }
        enemies.sort()
        var current: Int?
        var currentIsHero = false
        var bestMinion: Int?, bestHero: Int?, bestAggressor: Int?, lord: Int?
        var dMinion = Double.infinity, dHero = Double.infinity, dAggressor = Double.infinity, dLord = Double.infinity
        for k in enemies {
            let c = candidates[k]
            let d = c.pos.distanceSquared(to: pos)
            if c.id == currentID {
                current = c.index
                currentIsHero = c.kind == .hero || c.kind == .dummy
            }
            switch c.kind {
            case .minion:
                if d < dMinion { dMinion = d; bestMinion = c.index }
            case .monster:
                if d < dLord { dLord = d; lord = c.index }
            default:
                if d < dHero { dHero = d; bestHero = c.index }
                if c.kind == .hero && aggressorIDs.contains(c.id), d < dAggressor {
                    dAggressor = d
                    bestAggressor = c.index
                }
            }
        }
        if currentIsHero { return current }
        return bestAggressor ?? lord ?? current ?? bestMinion ?? bestHero
    }

    /// 構造物の攻撃が届く距離か（射程 + 双方の半径。CombatSystem と同じ基準）。
    static func inReach(_ tower: Unit, _ v: Unit) -> Bool {
        let reach = tower.stats.attackRange + tower.radius + v.radius
        return tower.pos.distanceSquared(to: v.pos) <= reach * reach
    }

    // MARK: - ダメージ

    /// 構造物（塔 / ベース）の通常攻撃 1 発のダメージ。CombatSystem が構造物の攻撃を放つ時に呼び、確定ダメージとして当てる
    /// （MLBB: 塔のダメージは確定ダメージで、軽減できない。ダメージは撃った時に決まる）。
    /// - ヒーロー: 攻撃 ×（1 + 0.75 × 連続命中の回数）。20 発目で止まる。最初の 1 発は −10%。2 秒当てなければ戻る。
    /// - ミニオン: 最大 HP の割合（近接 45% / 遠隔 70% / 攻城 14%。MLBB の値は資料に無いので旧来の値）。
    /// - 召喚されたロードなど: 攻撃そのまま。
    public static func attackDamage(_ s: inout SimState, _ ctx: SimContext, towerIndex i: Int, targetIndex t: Int) -> Double {
        typealias T = Balance.Tower
        let tower = s.units[i]
        let target = s.units[t]
        switch target.kind {
        case .minion:
            let pct: Double
            switch target.minion?.type ?? .melee {
            case .melee: pct = Balance.towerMeleeMinionDamagePct
            case .ranged: pct = Balance.towerRangedMinionDamagePct
            case .siege: pct = Balance.towerSiegeMinionDamagePct
            }
            // CombatSystem は構造物の弾を確定ダメージ（防御・被ダメ軽減を無視）として適用する。
            // 最終的に最大 HP の pct だけ削れるよう、その際に掛かる与ダメ補正（DESIGN §5 の 3）をあらかじめ打ち消しておく
            let bonus = max(0.05, 1 + tower.stats.damageBonus)
            return pct * target.stats.maxHP / bonus
        case .hero, .dummy:
            var hits = 0
            if let td = tower.tower, td.rampTargetID == target.id, let last = td.rampLastAt,
               s.time - last <= T.rampResetTime + 1e-6 {
                hits = min(td.rampHits, T.rampMaxHits - 1)
            }
            s.units[i].tower?.rampTargetID = target.id
            s.units[i].tower?.rampHits = hits + 1
            s.units[i].tower?.rampLastAt = s.time
            let first = hits == 0 ? T.firstHitMultiplier : 1
            return tower.stats.attack * (1 + T.rampPerHit * Double(hits)) * first
        default:
            return tower.stats.attack
        }
    }

    /// 構造物が受けるダメージの倍率。CombatSystem.applyDamage が呼ぶ。
    /// エネルギーシールド −30%・インナーの保護 −50%・バックドアの保護 −50%（射程内に敵ミニオンがいない時。ミニオン以外から）・
    /// ミニオンからベースへ −50%・攻城ミニオン ×1.5。
    public static func damageTakenMultiplier(_ s: SimState, _ ctx: SimContext, structureIndex i: Int,
                                             sourceIndex: Int?) -> Double {
        typealias T = Balance.Tower
        guard i >= 0, i < s.units.count, s.units[i].isStructure else { return 1 }
        var m = 1.0
        // エネルギーシールド（アウター、開始〜5:00）: 被ダメ −30%（攻撃者を問わない）
        if s.units[i].kind == .tower, s.units[i].tower?.tier == .outer, hasTurretShield(s.units[i]) {
            m *= 1 - T.shieldReduction
        }
        // インナーの保護: 同じレーンのアウターが 8:00 までに壊れてから 1 分間
        if let until = s.units[i].tower?.guardUntil, s.time < until { m *= 1 - T.innerGuardReduction }
        guard let a = sourceIndex, a >= 0, a < s.units.count else { return m }
        if s.units[a].kind == .minion {
            if s.units[a].minion?.type == .siege { m *= Balance.siegeStructureDamageMultiplier }
            if s.units[i].kind == .core { m *= 1 - T.coreMinionDamageReduction }
            return m
        }
        // バックドアの保護: 射程内に攻める側のミニオンがいなければ −50%（ヒーロー・召喚されたロードなど、ミニオン以外から）
        if !escorted(s, structureIndex: i) { m *= 1 - T.backdoorReduction }
        return m
    }

    /// 構造物の射程内に、攻める側（構造物の敵）のミニオンがいるか。
    public static func escorted(_ s: SimState, structureIndex i: Int) -> Bool {
        let team = s.units[i].team
        let pos = s.units[i].pos
        let reach = s.units[i].stats.attackRange + s.units[i].radius
        for k in s.units.indices where s.units[k].kind == .minion && s.units[k].isAlive {
            let t = s.units[k].team
            guard t != team, t != .neutral else { continue }
            let r = reach + s.units[k].radius
            if s.units[k].pos.distanceSquared(to: pos) <= r * r { return true }
        }
        return false
    }

    /// 味方のアウタータワーのエネルギーシールドに守られているか（シールドがある間、近くの味方ヒーローの被ダメ −15%）。
    /// 近くの範囲は資料に無いので塔の射程（届く距離）。
    public static func shieldGuardsHero(_ s: SimState, heroIndex h: Int) -> Bool {
        guard s.time < Balance.Tower.shieldDuration else { return false }
        let team = s.units[h].team
        let pos = s.units[h].pos
        for k in s.units.indices where s.units[k].kind == .tower && s.units[k].team == team && s.units[k].isAlive {
            guard s.units[k].tower?.tier == .outer, hasTurretShield(s.units[k]) else { continue }
            let r = s.units[k].stats.attackRange + s.units[k].radius + s.units[h].radius
            if s.units[k].pos.distanceSquared(to: pos) <= r * r { return true }
        }
        return false
    }

    // MARK: - 保護（塔が壊れた時）

    /// 塔が壊れた時の次の塔の保護（DeathSystem.structureDeath が呼ぶ）。
    /// アウターが 8:00 までに壊れたら同じレーンのインナーに 1 分間の被ダメ −50%、
    /// インナーが 12:00 までに壊れたら同じレーンのベースタワーの聖なる防御を待機させる。
    static func onTowerDestroyed(_ s: inout SimState, victimIndex v: Int) {
        typealias T = Balance.Tower
        guard s.units[v].kind == .tower, let td = s.units[v].tower, let lane = td.lane else { return }
        let team = s.units[v].team
        let next: TowerTier
        switch td.tier {
        case .outer:
            guard s.time < T.innerGuardWindow else { return }
            next = .inner
        case .inner:
            guard s.time < T.holyDefenseWindow else { return }
            next = .base
        case .base:
            return
        }
        for k in s.units.indices where s.units[k].kind == .tower && s.units[k].team == team && s.units[k].isAlive {
            guard s.units[k].tower?.lane == lane, s.units[k].tower?.tier == next else { continue }
            if next == .inner {
                s.units[k].tower?.guardUntil = s.time + T.innerGuardDuration
            } else {
                s.units[k].tower?.holyDefenseArmed = true
            }
        }
    }

    /// ベースタワーの聖なる防御: 待機中に敵ミニオンが射程に入ったら 1 度だけ発動する（12:00 を過ぎたら発動しない）。
    /// その波（射程の少し外までの敵ミニオン）に最大 HP の 80% の確定ダメージ。射程内の敵ミニオン（ロードは除く）と敵ヒーローを押し返す。
    static func holyDefense(_ s: inout SimState, _ ctx: SimContext, _ i: Int, candidates: [WorldCandidate],
                            grid: WorldSpatialIndex) {
        typealias T = Balance.Tower
        guard s.time < T.holyDefenseWindow else {
            s.units[i].tower?.holyDefenseArmed = nil
            return
        }
        let team = s.units[i].team
        let pos = s.units[i].pos
        let reach = s.units[i].stats.attackRange + s.units[i].radius
        var triggered = false
        var wave: [Int] = []
        var pushed: [Int] = []
        grid.forEach(near: pos, radius: reach + T.holyDefenseWaveMargin + 80) { k in
            let c = candidates[k]
            guard c.team != team, c.team != .neutral, c.kind == .minion || c.kind == .hero else { return }
            let d2 = c.pos.distanceSquared(to: pos)
            let inRange = d2 <= (reach + c.radius) * (reach + c.radius)
            if c.kind == .minion {
                if inRange { triggered = true }
                let rw = reach + T.holyDefenseWaveMargin + c.radius
                if d2 <= rw * rw { wave.append(c.index) }
            }
            if inRange { pushed.append(c.index) }
        }
        guard triggered else { return }
        s.units[i].tower?.holyDefenseArmed = nil
        wave.sort()
        pushed.sort()
        let id = s.units[i].id
        for m in wave where s.units[m].isAlive {
            CombatSystem.applyDamage(&s, ctx, sourceID: id, targetIndex: m,
                                     amount: T.holyDefenseMinionDamagePct * s.units[m].stats.maxHP,
                                     type: .trueDamage, source: .tower)
        }
        for u in pushed where s.units[u].isAlive {
            CombatSystem.applyCC(&s, ctx, sourceID: id, targetIndex: u, cc: .knockback, isUltimate: false, from: pos)
        }
    }

    // MARK: - ベース

    /// ベースは 5 秒ごとに 165 回復する。
    static func regenerate(_ s: inout SimState, _ i: Int) {
        typealias T = Balance.Tower
        guard let at = s.units[i].tower?.regenAt else {
            s.units[i].tower?.regenAt = s.time + T.coreRegenInterval
            return
        }
        guard s.time + 1e-9 >= at else { return }
        let next = at + T.coreRegenInterval
        s.units[i].tower?.regenAt = next > s.time ? next : s.time + T.coreRegenInterval
        s.units[i].hp = min(s.units[i].stats.maxHP, s.units[i].hp + T.coreRegenAmount)
    }

    // MARK: - 無敵判定

    /// 構造物が現在無敵か（眠っているアウター / 同レーンの前段タワー生存中 / ベースはベースタワーが 1 本も落ちていない間）。
    public static func isInvulnerable(_ s: SimState, _ ctx: SimContext, index i: Int) -> Bool {
        guard i >= 0, i < s.units.count, s.units[i].isStructure, let td = s.units[i].tower else { return false }
        let team = s.units[i].team
        if s.units[i].kind == .core {
            for k in s.units.indices where s.units[k].kind == .tower && s.units[k].team == team && !s.units[k].isAlive {
                if s.units[k].tower?.tier == .base { return false }
            }
            return true
        }
        if isAsleep(s, index: i) { return true }
        for k in s.units.indices where s.units[k].kind == .tower && s.units[k].team == team && s.units[k].isAlive {
            guard let other = s.units[k].tower else { continue }
            if other.lane == td.lane && other.tier.rawValue < td.tier.rawValue { return true }
        }
        return false
    }
}
