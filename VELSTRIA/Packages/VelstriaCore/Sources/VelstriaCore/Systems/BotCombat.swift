import Foundation

// 担当: core-bots
// 戦闘判断（DESIGN §10）: 戦力比による交戦/撤退、対象選択、予測射撃によるスキル、バトルスペル、範囲攻撃の回避。

/// 局地戦の見積もり。
struct BotFight {
    /// 味方戦力 / 敵戦力（ランチェスター二次則: ΣDPS × Σ実効HP）。
    var ratio: Double
    var allies: Int
    var enemies: Int
}

enum BotCombat {
    // MARK: - 交戦判断

    /// 敵ヒーローが近い時の行動（交戦・撤退）。行動を決めたら true。
    static func handleCombat(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                             _ mem: inout BotHeroMemory) -> Bool {
        let i = a.i
        let hpRatio = s.units[i].hpRatio
        let underTower = w.enemyStructure(covering: a.pos, team: a.team, margin: 0)
        let towerShootsMe = underTower.map { $0.targetID == a.id } ?? false

        if a.enemies.isEmpty {
            // 見えない敵に追われて撤退中なら帰還判断へ、タワーに撃たれていれば射程外へ
            if towerShootsMe, let st = underTower {
                leaveTower(s, ctx, &a, &mem, st)
                return true
            }
            if mem.goal == .teamfight { BotAI.setGoal(&mem, mem.position == .jungle ? .jungling : .laning, s.time) }
            return false
        }

        let fight = evaluateFight(s, w, a, center: a.pos)
        let outnumbered = fight.enemies > fight.allies + 1
        let retreatHP = outnumbered ? Balance.Bot.retreatHPOutnumbered : Balance.Bot.retreatHP
        let nearest = a.enemies[0]
        let threatRange = s.units[nearest.index].stats.attackRange + 450
        let threatened = nearest.distance < threatRange || s.time - s.units[i].lastDamagedTime < 1.5

        let target = pickTarget(s, ctx, w, a, mem)
        let killable = target.map { isKillable(s, ctx, a, $0.index) } ?? false

        // 撤退: HP 不足（確実なキルが目前でない限り）・劣勢
        if threatened {
            let desperate = hpRatio < retreatHP && !(killable && hpRatio > 0.12 && (target?.distance ?? .infinity) < 400)
            let losing = fight.ratio < Balance.Bot.fleeRatio && !(killable && fight.ratio > 0.4)
            if desperate || losing {
                retreat(&s, ctx, w, &a, &mem)
                return true
            }
        }
        if towerShootsMe, let st = underTower, !(a.profile.divesForKill && killable && hpRatio > 0.5) {
            leaveTower(s, ctx, &a, &mem, st)
            return true
        }

        guard let t = target else { return false }
        // 敵ヒーローに殴られている（反撃するか）
        let attackedByHero = s.time - s.units[i].lastDamagedTime < 1.5
            && s.unit(s.units[i].lastAttackerID).map { $0.kind == .hero && $0.team != a.team } == true
        // 集団戦の規模（2 対 2 以上）で味方が交戦中なら加勢する
        let groupFight = fight.allies >= 2 && fight.enemies >= 2
        let allyInTrouble = a.allies.contains {
            s.time - s.units[$0].lastCombatTime < 1.5 && s.units[$0].pos.distanceSquared(to: a.pos) < 1000 * 1000
        }
        var wantFight = fight.ratio >= a.profile.engageRatio || (killable && fight.ratio >= 0.7)
        if !wantFight && fight.ratio >= 1.0 && (attackedByHero || (groupFight && (allyInTrouble || mem.goal == .teamfight))) {
            wantFight = true
        }
        // 継続中の集団戦は多少の劣勢でも崩れない（逃げ遅れを防ぐため撤退比率より上なら続ける）
        if !wantFight && mem.goal == .teamfight && groupFight && fight.ratio >= 0.85 { wantFight = true }
        guard wantFight else {
            if mem.goal == .teamfight { BotAI.setGoal(&mem, mem.position == .jungle ? .jungling : .laning, s.time) }
            return false
        }
        return teamfight(&s, ctx, w, &a, &mem, target: t, killable: killable)
    }

    /// 対象を攻撃する（スキル・スペル・追跡制限・カイト）。行動したら true。
    static func teamfight(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                          _ mem: inout BotHeroMemory, target t: BotSighting, killable: Bool) -> Bool {
        let i = a.i
        if mem.goal != .teamfight {
            mem.fightAnchor = a.pos
            mem.fightStart = s.time
        }
        let reach = s.units[i].stats.attackRange + s.units[i].radius + s.units[t.index].radius
        // 深追いしない: 開始地点から離れすぎ・敵タワー下（確実なキルの突入を除く）
        let targetTower = w.enemyStructure(covering: t.pos, team: a.team, margin: 0)
        let dive = a.profile.divesForKill && killable && s.units[i].hpRatio > 0.5
        if t.distance > reach + 40 {
            let tooFar = t.pos.distance(to: mem.fightAnchor) > Balance.Bot.chaseLimit
            if (targetTower != nil && !dive) || tooFar {
                BotAI.setGoal(&mem, mem.position == .jungle ? .jungling : .laning, s.time)
                return false
            }
        }
        BotAI.setGoal(&mem, .teamfight, s.time)

        useOffensiveSpells(&s, ctx, &a, &mem, target: t, killable: killable, reach: reach)
        castSkills(&s, ctx, &a, &mem, target: t, fighting: true)

        // 遠隔: 近接に詰められたら攻撃の合間に下がる
        if a.isRanged, s.units[i].windupRemaining == nil, s.units[i].attackCooldown > 0.3 {
            if let diver = a.enemies.first(where: { $0.distance < Balance.Bot.kiteDistance && s.units[$0.index].hero?.isRanged == false }) {
                let away = (a.pos - diver.pos).normalized
                let safe = safePoint(s, ctx, w, a)
                let dir = (away * 0.6 + (safe - a.pos).normalized * 0.4).normalized
                a.emit(.moveTo(point: BotAI.safeGoal(ctx, team: a.team, a.pos + dir * 220)))
                mem.lastMoveGoal = nil
                return true
            }
        }
        BotAI.attack(s, &a, &mem, t.index)
        return true
    }

    /// 局地戦の戦力比。霧の中の敵は最大 HP で数える（見えない HP は読まない）。
    static func evaluateFight(_ s: SimState, _ w: BotWorld, _ a: BotAgent, center: Vec2) -> BotFight {
        var aD = 0.0, aH = 0.0, eD = 0.0, eH = 0.0
        let me = BotAI.strength(s, a.i)
        aD += me.dps
        aH += me.ehp
        var allies = 1
        for h in a.allies {
            let st = BotAI.strength(s, h)
            // 泉に居るだけの味方は戦力に数えない
            if s.units[h].pos.distanceSquared(to: center) > 1300 * 1300 { continue }
            aD += st.dps
            aH += st.ehp
            allies += 1
        }
        var enemies = 0
        for e in a.enemies {
            let st = BotAI.strength(s, e.index)
            eD += st.dps
            eH += st.ehp
            enemies += 1
        }
        for g in a.ghosts where g.distance < 1100 {
            let st = BotAI.strength(s, g.index)
            let full = s.units[g.index].stats.maxHP / max(1, s.units[g.index].hp + s.units[g.index].totalShield)
            eD += st.dps
            eH += st.ehp * max(1, full)
            enemies += 1
        }
        // 構造物
        if let st = w.alliedStructure(covering: center, team: a.team, margin: 150) {
            aD += s.units[st.index].stats.attack * 1.5
            aH += 2500
        }
        if let st = w.enemyStructure(covering: center, team: a.team, margin: 150) {
            eD += s.units[st.index].stats.attack * 1.5
            eH += 2500
        }
        // ミニオン（近くのものだけ）
        let r2 = 650.0 * 650.0
        for m in w.minions where m.pos.distanceSquared(to: center) <= r2 {
            if m.team == a.team {
                aD += 22
                aH += 200
            } else if m.isVisible(to: a.team) {
                eD += 22
                eH += 200
            }
        }
        let ratio = (aD * aH) / max(1, eD * eH)
        return BotFight(ratio: ratio, allies: allies, enemies: enemies)
    }

    /// 対象選択: 倒せる相手 > 実効 HP の低い相手 > キャリー（遠隔・魔法）。霧の中は追わない。
    static func pickTarget(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent,
                           _ mem: BotHeroMemory) -> BotSighting? {
        let range = s.units[a.i].stats.attackRange + s.units[a.i].radius
        var best: BotSighting?
        var bestScore = -Double.infinity
        for e in a.enemies {
            let gap = e.distance - range - s.units[e.index].radius
            if gap > 750 { continue }
            if CombatSystem.isInvulnerable(s, ctx, e.index) { continue }
            let u = s.units[e.index]
            var score = (1 - u.hpRatio) * 2.2
            if isKillable(s, ctx, a, e.index) { score += 3 }
            switch u.hero?.role {
            case .ranger?, .arcanist?: score += 0.8
            case .assassin?: score += 0.4
            case .support?: score += 0.2
            default: break
            }
            // 実効 HP の低さ（2000 基準）
            score += max(0, 1 - CombatSystem.effectiveHealth(u) / 4000)
            score -= max(0, gap) / 350
            if w.enemyStructure(covering: e.pos, team: a.team, margin: 0) != nil { score -= 2.5 }
            if e.id == mem.targetID { score += 0.6 }
            if score > bestScore {
                bestScore = score
                best = e
            }
        }
        return best
    }

    /// 数秒の集中攻撃で倒せるか。
    static func isKillable(_ s: SimState, _ ctx: SimContext, _ a: BotAgent, _ t: Int) -> Bool {
        let hp = max(0, s.units[t].hp) + s.units[t].totalShield
        return BotAI.burst(s, ctx, a.i, target: t) >= hp
    }

    // MARK: - 撤退

    /// 最寄りの味方タワー（自陣側）の後ろへ下がる。
    static func retreat(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                        _ mem: inout BotHeroMemory) {
        BotAI.setGoal(&mem, .retreat, s.time)
        mem.targetID = nil
        useDefensiveSpells(&s, ctx, w, &a, &mem, fighting: false)
        castEscapeSkill(&s, ctx, w, &a, &mem)
        BotAI.move(s, ctx, &a, &mem, to: safePoint(s, ctx, w, a))
    }

    /// 撤退先: 自分より泉寄りにある最寄りの味方構造物の後ろ（無ければ泉）。
    static func safePoint(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent) -> Vec2 {
        let fountain = ctx.map.fountain(a.team)
        let myHome = a.pos.distance(to: fountain)
        var best: BotStructureInfo?
        var bestD = Double.infinity
        for st in w.structures where st.team == a.team {
            let home = st.pos.distance(to: fountain)
            guard home < myHome - 150 else { continue }
            let d = st.pos.distanceSquared(to: a.pos)
            if d < bestD {
                bestD = d
                best = st
            }
        }
        guard let st = best else { return fountain }
        // タワーに近すぎる（射程の内側深く）なら、さらに泉側の地点
        let back = (fountain - st.pos).normalized
        let p = st.pos + back * 380
        if a.pos.distanceSquared(to: p) < 200 * 200 && !a.enemies.isEmpty { return fountain }
        return p
    }

    /// 敵タワーの射程外へ出る（レーンを自陣側へ戻る）。
    static func leaveTower(_ s: SimState, _ ctx: SimContext, _ a: inout BotAgent, _ mem: inout BotHeroMemory,
                           _ st: BotStructureInfo) {
        let away = (a.pos - st.pos).normalized
        let home = (ctx.map.fountain(a.team) - a.pos).normalized
        var dir = (away + home).normalized
        if dir == .zero { dir = home }
        let dist = st.reach + Balance.heroRadius + Balance.Bot.towerSafetyMargin + 60
        var p = st.pos + dir * dist
        if p.distance(to: a.pos) < 150 { p = a.pos + dir * 200 }
        mem.targetID = nil
        BotAI.move(s, ctx, &a, &mem, to: p)
    }

    // MARK: - 範囲攻撃の回避

    /// 予告中（遅延あり）の敵の円形範囲に居れば外へ出る。移動したら true。
    static func dodgeZones(_ s: SimState, _ ctx: SimContext, _ a: inout BotAgent, _ mem: inout BotHeroMemory) -> Bool {
        guard a.difficulty != .easy, !s.zones.isEmpty else { return false }
        for z in s.zones where z.team != a.team && !z.triggered && !z.done && z.delay > 0 && z.payload.affectsEnemies {
            guard case .circle = z.shape else { continue }
            // Normal は猶予がある時だけ避ける
            if a.difficulty == .normal && z.delay < 0.25 { continue }
            let r = z.radius + Balance.heroRadius
            guard a.pos.distanceSquared(to: z.center) < r * r else { continue }
            var dir = (a.pos - z.center).normalized
            if dir == .zero { dir = (ctx.map.fountain(a.team) - z.center).normalized }
            let p = BotAI.safeGoal(ctx, team: a.team, z.center + dir * (r + 90))
            a.emit(.moveTo(point: p))
            mem.lastMoveGoal = p
            return true
        }
        return false
    }

    // MARK: - スキル

    /// 敵ヒーローへのスキル（1 回の意思決定で最大 1 つ）。Ult は複数を巻き込むか倒せる時だけ。
    static func castSkills(_ s: inout SimState, _ ctx: SimContext, _ a: inout BotAgent, _ mem: inout BotHeroMemory,
                           target t: BotSighting, fighting: Bool) {
        guard s.units[a.i].canCast, s.time - mem.lastSkillTime >= 0.3, let h = s.units[a.i].hero,
              let hdef = ctx.master.hero(h.heroID) else { return }
        let killable = isKillable(s, ctx, a, t.index)
        for slot in [SkillSlot.ultimate, .skill1, .skill2, .skill3] {
            guard SkillSystem.canCast(s, ctx, heroIndex: a.i, slot: slot),
                  let def = ctx.master.skill(hero: h.heroID, slot: slot) else { continue }
            guard s.units[a.i].resource + 1e-6 >= SkillSystem.cost(for: def, resource: h.resourceKind) else { continue }
            let tg = SkillCatalog.targeting(for: def, hero: hdef)
            guard tg.archetype != .passive else { continue }
            if slot == .ultimate {
                let center = tg.aim == .none ? a.pos : t.pos
                let crowd = enemiesNear(a, center, radius: max(tg.radius * 1.4, 300))
                guard killable || crowd >= 2 else { continue }
            }
            guard let target = aim(&s, ctx, a, &mem, tg, slot: slot, target: t, fighting: fighting) else { continue }
            // 難易度によるスキル頻度
            guard s.rng.nextDouble() < a.profile.skillChance else { return }
            a.emit(.castSkill(slot: slot, target: target))
            mem.lastSkillTime = s.time
            return
        }
    }

    /// 撤退時の移動スキル（突進・ブリンクを安全方向へ）。
    static func castEscapeSkill(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                                _ mem: inout BotHeroMemory) {
        guard a.nearestEnemyDistance < 500, s.units[a.i].canCast, let h = s.units[a.i].hero,
              let hdef = ctx.master.hero(h.heroID) else { return }
        for slot in [SkillSlot.skill2, .skill1, .skill3] {
            guard SkillSystem.canCast(s, ctx, heroIndex: a.i, slot: slot),
                  let def = ctx.master.skill(hero: h.heroID, slot: slot),
                  s.units[a.i].resource + 1e-6 >= SkillSystem.cost(for: def, resource: h.resourceKind) else { continue }
            let tg = SkillCatalog.targeting(for: def, hero: hdef)
            guard tg.archetype == .dashStrike || tg.archetype == .blinkEmpower else { continue }
            let dir = (safePoint(s, ctx, w, a) - a.pos).normalized
            guard dir != .zero else { return }
            a.emit(.castSkill(slot: slot, target: .direction(dir)))
            mem.lastSkillTime = s.time
            return
        }
    }

    /// ミニオン・モンスターの集団へ範囲スキル（押し込み・ジャングル）。
    static func castFarmSkills(_ s: inout SimState, _ ctx: SimContext, _ a: inout BotAgent, _ mem: inout BotHeroMemory,
                               targets: [Int], minCluster: Int) {
        guard !targets.isEmpty, s.units[a.i].canCast, s.time - mem.lastSkillTime >= 0.6,
              let h = s.units[a.i].hero, let hdef = ctx.master.hero(h.heroID) else { return }
        let maxRes = s.units[a.i].stats.maxResource
        guard maxRes <= 0 || s.units[a.i].resource >= maxRes * a.profile.farmSkillResource else { return }
        for slot in [SkillSlot.skill1, .skill3, .skill2] {
            guard SkillSystem.canCast(s, ctx, heroIndex: a.i, slot: slot),
                  let def = ctx.master.skill(hero: h.heroID, slot: slot),
                  s.units[a.i].resource + 1e-6 >= SkillSystem.cost(for: def, resource: h.resourceKind) else { continue }
            let tg = SkillCatalog.targeting(for: def, hero: hdef)
            switch tg.archetype {
            case .passive, .dashStrike, .leapSlam, .targetedBlink, .blinkEmpower, .teamHeal, .multiStrike:
                continue
            default:
                break
            }
            // 最も多くを巻き込める中心
            let radius = max(120, tg.radius)
            var bestCenter: Int?
            var bestCount = 0
            for c in targets {
                let p = s.units[c].pos
                guard p.distance(to: a.pos) <= max(tg.range, radius) + 50 else { continue }
                var n = 0
                for o in targets where s.units[o].pos.distanceSquared(to: p) <= radius * radius { n += 1 }
                if n > bestCount {
                    bestCount = n
                    bestCenter = c
                }
            }
            guard let c = bestCenter, bestCount >= minCluster else { continue }
            let p = s.units[c].pos
            let target: SkillTarget
            switch tg.aim {
            case .none:
                guard p.distance(to: a.pos) <= max(tg.range, tg.radius) else { continue }
                target = .none
            case .direction:
                let d = (p - a.pos).normalized
                guard d != .zero else { continue }
                target = .direction(d)
            case .point:
                target = .point(a.pos + (p - a.pos).clamped(maxLength: tg.range))
            case .unit:
                target = .unit(s.units[c].id)
            }
            a.emit(.castSkill(slot: slot, target: target))
            mem.lastSkillTime = s.time
            return
        }
    }

    /// 照準（予測射撃）。撃つべきでなければ nil。
    static func aim(_ s: inout SimState, _ ctx: SimContext, _ a: BotAgent, _ mem: inout BotHeroMemory,
                    _ tg: SkillTargeting, slot: SkillSlot, target t: BotSighting, fighting: Bool) -> SkillTarget? {
        let me = a.pos
        let tr = s.units[t.index].radius
        let dist = t.distance

        // 味方対象（回復・シールド）
        if tg.targetsAllies || tg.archetype == .teamHeal || tg.archetype == .healZone {
            return aimSupport(s, a, tg, target: t)
        }
        switch tg.archetype {
        case .dashStrike, .leapSlam, .targetedBlink:
            // 突入系は交戦中のみ・敵タワー下には飛び込まない
            guard fighting else { return nil }
        case .blinkEmpower:
            guard fighting, dist <= s.units[a.i].stats.attackRange + 200 else { return nil }
            // 自陣側へ横にずれて次の通常攻撃を強化
            var side = (t.pos - me).normalized.perpendicular
            if side.dot(ctx.map.fountain(a.team) - me) < 0 { side = -side }
            return side == .zero ? nil : .direction(side)
        default:
            break
        }

        switch tg.aim {
        case .none:
            let r = max(tg.range, tg.radius) + tr
            return dist <= r ? SkillTarget.none : nil
        case .unit:
            return dist <= tg.range + tr ? .unit(t.id) : nil
        case .direction:
            let reachLimit = tg.range + tr + (tg.archetype == .dashStrike ? 100 : 0)
            guard dist <= reachLimit else { return nil }
            let travel = travelTime(tg, slot: slot, distance: dist)
            let p = predicted(&s, a, &mem, t, travel: travel, radius: tg.radius)
            let d = (p - me).normalized
            return d == .zero ? nil : .direction(d)
        case .point:
            let extra = tg.archetype == .leapSlam ? 200.0 : tg.radius * 0.5
            guard dist <= tg.range + extra + tr else { return nil }
            let travel = travelTime(tg, slot: slot, distance: dist)
            let p = predicted(&s, a, &mem, t, travel: travel, radius: tg.radius)
            return .point(me + (p - me).clamped(maxLength: tg.range + (tg.archetype == .leapSlam ? 200 : 0)))
        }
    }

    /// 回復・シールド系: 最も HP 割合の低い味方（自分を含む）が傷ついていれば撃つ。
    static func aimSupport(_ s: SimState, _ a: BotAgent, _ tg: SkillTargeting, target t: BotSighting) -> SkillTarget? {
        var worst = a.i
        var worstRatio = s.units[a.i].hpRatio
        var hurt = s.units[a.i].hpRatio < 0.6 ? 1 : 0
        let r = max(tg.range, tg.archetype == .teamHeal ? 1500 : tg.range)
        for h in a.allies where s.units[h].pos.distanceSquared(to: a.pos) <= r * r {
            let ratio = s.units[h].hpRatio
            if ratio < 0.6 { hurt += 1 }
            if ratio < worstRatio {
                worstRatio = ratio
                worst = h
            }
        }
        switch tg.aim {
        case .none:
            // 味方全体回復: 誰かが危険、または複数が傷ついている
            return worstRatio < 0.4 || hurt >= 2 ? SkillTarget.none : nil
        case .unit:
            return worstRatio < 0.55 ? .unit(s.units[worst].id) : nil
        case .point:
            // 回復ゾーン: 傷ついた味方の足元、居なければ敵へ（ダメージ/CC）
            if worstRatio < 0.6 {
                return .point(a.pos + (s.units[worst].pos - a.pos).clamped(maxLength: tg.range))
            }
            return t.distance <= tg.range + tg.radius * 0.5 ? .point(a.pos + (t.pos - a.pos).clamped(maxLength: tg.range)) : nil
        case .direction:
            let d = (t.pos - a.pos).normalized
            return t.distance <= tg.range && d != .zero ? .direction(d) : nil
        }
    }

    /// スキルが対象に届くまでの時間（弾速・予告時間・突進速度）。
    static func travelTime(_ tg: SkillTargeting, slot: SkillSlot, distance: Double) -> Double {
        switch tg.archetype {
        case .lineSkillshot, .piercingLine: return 0.1 + distance / 1600
        case .groundAoE: return slot == .ultimate ? 1.0 : 0.5
        case .healZone: return 0.5
        case .leapSlam: return 0.45
        case .dashStrike: return distance / 1200
        case .cone: return 0.12
        default: return 0.25
        }
    }

    /// 予測位置: 現在位置 + 速度 × 到達時間。難易度の精度で外れた照準を引く（state.rng）。
    static func predicted(_ s: inout SimState, _ a: BotAgent, _ mem: inout BotHeroMemory, _ t: BotSighting,
                          travel: Double, radius: Double) -> Vec2 {
        let roll = s.rng.nextDouble()
        let angle: Double
        let lead: Double
        if roll < a.profile.accuracy {
            // 狙いどおり（わずかなぶれのみ）
            angle = (roll / max(1e-9, a.profile.accuracy) - 0.5) * 0.05
            lead = 1
        } else {
            // 外れ: 先読みの量と角度を誤る
            let u = s.rng.nextDouble()
            lead = u * 2
            let sign: Double = s.rng.nextDouble() < 0.5 ? -1 : 1
            angle = sign * (0.12 + 0.25 * u)
        }
        mem.aimAngleError = angle
        mem.aimLeadScale = lead
        let p = t.pos + t.velocity * (travel * lead)
        return a.pos + (p - a.pos).rotated(by: angle)
    }

    static func enemiesNear(_ a: BotAgent, _ center: Vec2, radius: Double) -> Int {
        var n = 0
        for e in a.enemies where e.pos.distanceSquared(to: center) <= radius * radius { n += 1 }
        return n
    }

    // MARK: - バトルスペル

    /// 攻撃的なスペル（点火・星鎖・キルのための瞬歩/加速陣）。
    static func useOffensiveSpells(_ s: inout SimState, _ ctx: SimContext, _ a: inout BotAgent,
                                   _ mem: inout BotHeroMemory, target t: BotSighting, killable: Bool, reach: Double) {
        guard let h = s.units[a.i].hero else { return }
        let tu = s.units[t.index]
        for idx in h.spells.indices where SpellSystem.canCast(s, ctx, heroIndex: a.i, spellIndex: idx) {
            switch h.spells[idx] {
            case "BS07":
                let ignite = 70 + 20 * Double(h.level)
                let myHit = CombatSystem.estimateBasicAttackDamage(s, ctx, attacker: a.i, target: t.index)
                if t.distance <= Balance.Bot.igniteRange && (tu.hp + tu.totalShield <= ignite + myHit * 2 || tu.hpRatio < 0.3) {
                    a.emit(.castSpell(index: idx, target: .unit(t.id)))
                    return
                }
            case "BS10":
                let diver = a.enemies.first { $0.distance < 400 && s.units[$0.index].hero?.isRanged == false }
                if let d = diver, d.distance <= Balance.Bot.chainRange {
                    a.emit(.castSpell(index: idx, target: .unit(d.id)))
                    return
                }
                if t.distance <= Balance.Bot.chainRange && tu.hpRatio < 0.5 {
                    a.emit(.castSpell(index: idx, target: .unit(t.id)))
                    return
                }
            case "BS01":
                // 瞬歩で詰めて倒す（Normal 以上）
                let gap = t.distance - reach
                if a.difficulty != .easy, killable, tu.hpRatio < 0.25, gap > 60, gap < Balance.Bot.flashDistance - 20 {
                    let d = (t.pos - a.pos).normalized
                    if d != .zero {
                        a.emit(.castSpell(index: idx, target: .direction(d)))
                        return
                    }
                }
            case "BS06":
                if killable, t.distance > reach + 200 {
                    a.emit(.castSpell(index: idx, target: .none))
                    return
                }
            default:
                break
            }
        }
    }

    /// 防御的なスペル（浄化・治癒波・鉄壁・逃げの瞬歩/加速陣/虚像）。
    static func useDefensiveSpells(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                                   _ mem: inout BotHeroMemory, fighting: Bool) {
        guard let h = s.units[a.i].hero else { return }
        let u = s.units[a.i]
        let hpRatio = u.hpRatio
        let hurtRecently = s.time - u.lastDamagedTime < 1.5
        let nearest = a.nearestEnemyDistance
        for idx in h.spells.indices where SpellSystem.canCast(s, ctx, heroIndex: a.i, spellIndex: idx) {
            switch h.spells[idx] {
            case "BS02":
                let hardCC = u.has(.stun) || u.has(.root) || (u.has(.silence) && fighting)
                    || (!fighting && (u.status(.slow)?.magnitude ?? 0) >= 0.4)
                if hardCC && nearest < 900 {
                    a.emit(.castSpell(index: idx, target: .none))
                    return
                }
            case "BS03":
                var allyLow = false
                for al in a.allies where s.units[al].hpRatio < 0.2 && s.units[al].pos.distance(to: a.pos) <= Balance.Bot.healWaveRange {
                    allyLow = true
                }
                if (hpRatio < 0.3 && hurtRecently) || (allyLow && nearest < 1000) {
                    a.emit(.castSpell(index: idx, target: .none))
                    return
                }
            case "BS04":
                if hpRatio < 0.3 && hurtRecently && nearest < 900 {
                    a.emit(.castSpell(index: idx, target: .none))
                    return
                }
            case "BS01":
                guard !fighting, u.canAct, hpRatio < 0.25, nearest < 450 else { continue }
                let d = (safePoint(s, ctx, w, a) - a.pos).normalized
                if d != .zero {
                    a.emit(.castSpell(index: idx, target: .direction(d)))
                    return
                }
            case "BS06":
                if !fighting && hpRatio < 0.45 && nearest < 650 {
                    a.emit(.castSpell(index: idx, target: .none))
                    return
                }
            case "BS08":
                if !fighting && hpRatio < 0.25 && nearest < 500 {
                    a.emit(.castSpell(index: idx, target: .none))
                    return
                }
            default:
                break
            }
        }
    }
}
