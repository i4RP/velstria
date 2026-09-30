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

    /// 敵ヒーローが近い時の行動（交戦・撤退・にらみ合い）。行動を決めたら true。
    /// 交戦中（goal == .teamfight）・撤退中は判断にヒステリシスを持たせ、1 回毎に行ったり来たりしない。
    static func handleCombat(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                             _ mem: inout BotHeroMemory) -> Bool {
        let i = a.i
        let hpRatio = s.units[i].hpRatio
        let underTower = w.enemyStructure(covering: a.pos, team: a.team, margin: 0)
        let towerShootsMe = underTower.map { $0.targetID == a.id && mustLeaveTower(s, w, a, mem, $0) } ?? false
        let role: BotGoal = mem.position == .jungle ? .jungling : .laning

        guard let nearest = a.enemies.first else {
            // 見えない敵に追われて撤退中なら帰還判断へ、タワーに撃たれていれば射程外へ
            if towerShootsMe, let st = underTower {
                leaveTower(s, ctx, &a, &mem, st)
                return true
            }
            if mem.goal == .teamfight { BotAI.setGoal(&mem, role, s.time) }
            return false
        }

        // 交戦地点（自分と最寄りの敵の中間）周辺の戦力比
        let center = (a.pos + nearest.pos) * 0.5
        let fight = evaluateFight(s, w, a, center: center)
        let outnumbered = fight.enemies > fight.allies + 1
        let retreatHP = outnumbered ? Balance.Bot.retreatHPOutnumbered : Balance.Bot.retreatHP
        let threatRange = s.units[nearest.index].stats.attackRange + 450
        let threatened = nearest.distance < threatRange || s.time - s.units[i].lastDamagedTime < 1.5
        let target = pickTarget(s, ctx, w, a, mem)
        let killable = target.map { isKillable(s, ctx, a, $0.index, world: w) } ?? false
        let reach = s.units[i].stats.attackRange + s.units[i].radius + Balance.heroRadius

        // 1. HP 不足 + 不利（DESIGN §10）: 撤退。勝っている戦い（戦力比 1.15 以上）は 15% までは続ける。
        //    目の前の確実なキルは除く。脅威から離れていても再交戦はしない（帰還判断へ）
        let winning = fight.ratio >= 1.15 && !outnumbered && hpRatio > 0.15
        if hpRatio < retreatHP && !winning
            && !(killable && hpRatio > 0.12 && (target?.distance ?? .infinity) < reach + 80) {
            if threatened {
                retreat(&s, ctx, w, &a, &mem)
                return true
            }
            if mem.goal == .teamfight { BotAI.setGoal(&mem, .retreat, s.time) }
            return false
        }
        // 2. 敵タワーに狙われている: 射程外へ（確実なキルの突入を除く）
        if towerShootsMe, let st = underTower, !(a.profile.divesForKill && killable && hpRatio > 0.5) {
            leaveTower(s, ctx, &a, &mem, st)
            return true
        }

        let skirmish = s.time < a.profile.groupStart && fight.allies < 3
            && mem.goal != .objective && mem.goal != .push && mem.goal != .defend
        let groupFight = fight.allies >= 2 && fight.enemies >= 2 && !skirmish
        // 1 対 1・レーンの 2 対 2 は明確な有利でのみ仕掛ける（互角の殴り合いでウェーブを放置しない）
        let engageAt = groupFight ? a.profile.engageRatio : a.profile.engageRatio + 0.25

        // 3. 撤退中: 十分な有利と体力が戻るまで撤退を続ける
        if mem.goal == .retreat && threatened && !(hpRatio >= 0.55 && fight.ratio >= engageAt + 0.3) {
            retreat(&s, ctx, w, &a, &mem)
            return true
        }

        // 4. 交戦中: 撤退比率を割るまで戦い続ける
        if mem.goal == .teamfight {
            if fight.ratio < Balance.Bot.fleeRatio && !(killable && fight.ratio > 0.45) && threatened {
                retreat(&s, ctx, w, &a, &mem)
                return true
            }
            if let t = target, teamfight(&s, ctx, w, &a, &mem, target: t, killable: killable) { return true }
            return posture(s, ctx, w, &a, &mem, nearest: nearest, fight: fight)
        }

        // 5. 交戦していない: 仕掛けるか・下がるか・にらみ合うか
        let attackedByHero = s.time - s.units[i].lastDamagedTime < 1.5
            && s.unit(s.units[i].lastAttackerID).map { $0.kind == .hero && $0.team != a.team } == true
        let allyInTrouble = a.allies.contains {
            s.time - s.units[$0].lastCombatTime < 1.5 && s.units[$0].pos.distanceSquared(to: a.pos) < 1100 * 1100
        }
        let wantFight = fight.ratio >= engageAt || (killable && fight.ratio >= 0.75)
            || (attackedByHero && fight.ratio >= 1.0) || (groupFight && allyInTrouble && fight.ratio >= 0.95)
        if wantFight, let t = target, teamfight(&s, ctx, w, &a, &mem, target: t, killable: killable) { return true }
        if fight.ratio < Balance.Bot.fleeRatio && threatened {
            retreat(&s, ctx, w, &a, &mem)
            return true
        }
        return posture(s, ctx, w, &a, &mem, nearest: nearest, fight: fight)
    }

    /// にらみ合い: 押し込み・防衛・オブジェクト中に敵の集団（2 人以上）の射程へ入りそうなら間合いを取る。
    /// 1 人相手・十分離れている時は何もしない（マクロの移動を止めて睨み合いのまま固まらないように）。
    static func posture(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                        _ mem: inout BotHeroMemory, nearest: BotSighting, fight: BotFight) -> Bool {
        let role: BotGoal = mem.position == .jungle ? .jungling : .laning
        if mem.goal == .teamfight { BotAI.setGoal(&mem, role, s.time) }
        // レーン戦・ジャングルは各ロジックが間合いを取る
        guard mem.goal == .push || mem.goal == .defend || mem.goal == .objective || mem.goal == .roaming,
              fight.enemies >= 2 else { return false }
        let keep = s.units[nearest.index].stats.attackRange + Balance.heroRadius * 2 + 150
        guard nearest.distance < keep else { return false }
        var dir = (a.pos - nearest.pos).normalized
        let home = (safePoint(s, ctx, w, a) - a.pos).normalized
        dir = (dir + home).normalized
        if dir == .zero { dir = home }
        BotAI.move(s, ctx, &a, &mem, to: nearest.pos + dir * (keep + 60))
        return true
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
            // 弱った相手（倒せる・HP 35% 未満）は自陣の塔に逃げ込むまで追う
            let limit = killable || s.units[t.index].hpRatio < 0.35 ? Balance.Bot.chaseLimit * 2 : Balance.Bot.chaseLimit
            let tooFar = t.pos.distance(to: mem.fightAnchor) > limit
            if (targetTower != nil && !dive) || tooFar { return false }
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

    /// 局地戦の戦力比（center の周囲 1400 の味方・敵）。霧の中の敵は最大 HP で数える（見えない HP は読まない）。
    static func evaluateFight(_ s: SimState, _ w: BotWorld, _ a: BotAgent, center: Vec2) -> BotFight {
        var aD = 0.0, aH = 0.0, eD = 0.0, eH = 0.0
        let r2 = 1400.0 * 1400.0
        var allies = 0
        for h in w.heroes where s.units[h].team == a.team && s.units[h].isAlive && s.units[h].hero?.isDead != true {
            guard h == a.i || s.units[h].pos.distanceSquared(to: center) <= r2 else { continue }
            let st = BotAI.strength(s, h)
            aD += st.dps
            aH += st.ehp
            allies += 1
        }
        var enemies = 0
        for e in a.enemies where e.pos.distanceSquared(to: center) <= r2 {
            let st = BotAI.strength(s, e.index)
            eD += st.dps
            eH += st.ehp
            enemies += 1
        }
        for g in a.ghosts where g.pos.distanceSquared(to: center) <= 1100 * 1100 {
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
        // ミニオン: 敵ヒーローを殴ると自分の近くの敵ミニオンが一斉にこちらを狙う（救援要請）。
        // 味方ミニオンは相手が反撃してきた時だけ加勢するので半分に数える
        let foe = a.enemies.first?.pos ?? center
        let m2 = 700.0 * 700.0
        for m in w.minions {
            if m.team != a.team, m.isVisible(to: a.team), m.pos.distanceSquared(to: a.pos) <= m2 {
                eD += s.units[m.index].stats.attack / 1.3
            } else if m.team == a.team, m.pos.distanceSquared(to: foe) <= m2 {
                aD += s.units[m.index].stats.attack / 2.6
            }
        }
        let ratio = (aD * aH) / max(1, eD * eH)
        return BotFight(ratio: ratio, allies: allies, enemies: enemies)
    }

    /// 対象選択: 倒せる相手 > 実効 HP の低い相手 > キャリー（遠隔・魔法）。霧の中は追わない。
    static func pickTarget(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent,
                           _ mem: BotHeroMemory) -> BotSighting? {
        let range = s.units[a.i].stats.attackRange + s.units[a.i].radius
        let mySpeed = MovementSystem.currentMoveSpeed(s, a.i)
        // 候補の中で最も倒しやすい実効 HP（相対評価の基準）
        var minEHP = Double.infinity
        for e in a.enemies where e.distance - range - s.units[e.index].radius <= 750 {
            minEHP = min(minEHP, CombatSystem.effectiveHealth(s.units[e.index]))
        }
        var best: BotSighting?
        var bestScore = -Double.infinity
        for e in a.enemies {
            let gap = e.distance - range - s.units[e.index].radius
            if gap > 750 { continue }
            if CombatSystem.isInvulnerable(s, ctx, e.index) { continue }
            let u = s.units[e.index]
            let killable = isKillable(s, ctx, a, e.index, world: w)
            // 逃げる相手に追いつけないなら追わない（射程内・倒せる相手を除く）
            if gap > 60 && !killable {
                let away = (e.pos - a.pos).normalized
                let fleeing = e.velocity.dot(away)
                if fleeing > mySpeed * 0.85 && gap > (a.isRanged ? 120 : 40) { continue }
            }
            // 柔らかい相手（実効 HP が低い）を優先し、硬い前衛を殴り続けない
            let ehp = CombatSystem.effectiveHealth(u)
            var score = 3.0 * minEHP / max(1, ehp) + (1 - u.hpRatio) * 1.5
            if killable { score += 3 }
            if gap <= 0 { score += 0.5 }
            switch u.hero?.role {
            case .ranger?, .arcanist?: score += 0.6
            case .assassin?: score += 0.3
            case .support?: score += 0.2
            default: break
            }
            score -= max(0, gap) / 300
            if w.enemyStructure(covering: e.pos, team: a.team, margin: 0) != nil { score -= 2.5 }
            if e.id == mem.targetID { score += 0.6 }
            // 味方と同じ相手を狙う（集中攻撃）
            for al in a.allies where s.units[al].attackTargetID == e.id { score += 0.7 }
            if score > bestScore {
                bestScore = score
                best = e
            }
        }
        return best
    }

    /// 自分と対象の近くに居る味方で倒せるか（集中攻撃のキル圏）。各自の瞬間火力に加え、遠隔は対象が
    /// 自陣の構造物へ逃げ込むまでの時間も撃ち続けられるとみなす（逃げる相手を射程で追い撃つ）。
    static func isKillable(_ s: SimState, _ ctx: SimContext, _ a: BotAgent, _ t: Int, world w: BotWorld? = nil) -> Bool {
        let hp = max(0, s.units[t].hp) + s.units[t].totalShield
        let tp = s.units[t].pos
        // 対象が安全圏（自陣の構造物の射程）に着くまでの秒数（2〜6 秒）
        var escape = 2.0
        if let w {
            var nearest = Double.infinity
            for st in w.structures where st.team == s.units[t].team {
                nearest = min(nearest, max(0, tp.distance(to: st.pos) - st.reach))
            }
            let speed = max(150, s.units[t].stats.moveSpeed)
            escape = min(6, max(2, nearest / speed))
        }
        func chase(_ h: Int) -> Double {
            guard s.units[h].hero?.isRanged == true else { return 0 }
            // 追いながら撃つので効率は半分程度
            return CombatSystem.estimateBasicAttackDamage(s, ctx, attacker: h, target: t) * s.units[h].stats.attackSpeed
                * escape * 0.5
        }
        var total = BotAI.burst(s, ctx, a.i, target: t, skills: a.skillsWork) + chase(a.i)
        if total >= hp { return true }
        for al in a.allies {
            let r = s.units[al].stats.attackRange + s.units[al].radius + s.units[t].radius + 250
            guard s.units[al].pos.distanceSquared(to: tp) <= r * r else { continue }
            // 味方のスキルは実際に使えているか分からないため通常攻撃のみで見積もる
            total += BotAI.burst(s, ctx, al, target: t, skills: false) + chase(al)
            if total >= hp { return true }
        }
        return false
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

    /// 敵構造物に狙われた時に射程外へ出るべきか。押し込み中は体力に余裕があれば数発受けて狙いを味方と回し、
    /// 落ちかけの構造物は味方と揃っていれば押し切る（全員が同じ塔で倒れないよう、連続命中が重なれば下がる）。
    static func mustLeaveTower(_ s: SimState, _ w: BotWorld, _ a: BotAgent, _ mem: BotHeroMemory,
                               _ st: BotStructureInfo) -> Bool {
        let hp = s.units[a.i].hpRatio
        let tower = s.units[st.index].tower
        let ramp = tower?.rampTargetID == a.id ? (tower?.rampHits ?? 0) : 0
        guard mem.goal == .push || mem.goal == .teamfight || mem.goal == .defend || mem.goal == .objective else { return true }
        var allies = 0
        for h in w.heroes where h != a.i && s.units[h].team == a.team && s.units[h].isAlive {
            if s.units[h].pos.distanceSquared(to: st.pos) < 1300 * 1300 { allies += 1 }
        }
        if st.hp < st.maxHP * 0.3 && allies >= 2 && hp > 0.25 { return false }
        return !(allies >= 1 && hp > 0.55 && ramp < 3)
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
            BotAI.noteSkillCast(&mem, slot: slot, tick: s.tick)
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
            BotAI.noteSkillCast(&mem, slot: slot, tick: s.tick)
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
            BotAI.noteSkillCast(&mem, slot: slot, tick: s.tick)
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
