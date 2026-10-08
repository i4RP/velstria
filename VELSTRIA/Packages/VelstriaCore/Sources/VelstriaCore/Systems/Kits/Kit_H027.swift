import Foundation

// 担当: kit-H027（docs/SKILL_KITS.md / docs/NEW_HEROES.md）
// H027 竜槍のジャルド = Velstria 版の Zilong（MLBB。調査: docs/kits/Zilong.md、対応表: 同ファイル末尾）。
//   パッシブ 竜の三連突き  — ダメージを与える（通常攻撃・スキル）たびに竜気 +1。3 つ（奥義中は 2 つ）で次の通常攻撃が
//                           射程の伸びた三連撃（1 撃 80 + 攻撃力 30%・命中ごとに 50 + 20% 回復）になる。
//                           HP 50% 未満の相手へは通常攻撃・スキルのダメージが常に +30（固定値）。
//   S1   槍の跳ね上げ      — 対象指定。敵を槍で跳ね上げて背後へ放り投げる（打ち上げ 0.8 秒）。
//   S2   竜牙の踏み込み    — 対象指定の突進。踏み込みざまにダメージ + 防御ダウン 2 秒、その後は通常攻撃へ。
//                           敵を倒す（0.5 秒以内に倒れた敵を含む）たびにクールダウンがリセットされる。
//   奥義 至高の武人        — 自己強化 7.5 秒: 移動速度 +40%・攻撃速度 +35/45/55%・スロウ解除と無効。
//                           三連突きは 2 回のダメージごとに発動する。ダメージ・CC は無い。
// 再使用の窓は Zilong に無いので使わない（SkillSystem.cast の経路は 3 スキルとも初回発動のみ）。
//
// 状態（KitState）:
//   ints[0]  = 竜気（0..3）            ints[1] = 今の通常攻撃で残っている三連突きの命中数（同 tick 内のみ）
//   timers[0] = 奥義の残り秒          timers[1] = 「直前に傷つけた敵が倒れたら S2 リセット」の窓（0.5 秒）
//   ids[0]   = 直前に傷つけた敵      ids[1]   = S2 の突進先の敵
//   reals[0] = S2 の突進ダメージ      reals[1] = S2 の防御ダウン量（固定値）

extension KitState {
    var jarldCharge: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var jarldFlurryHitsLeft: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var jarldUltRemaining: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var jarldResetWindow: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var jarldWatchedID: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }

    var jarldDashTargetID: EntityID {
        get { ids[1] }
        set { ids[1] = newValue }
    }

    var jarldDashDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }

    var jarldDashShred: Double {
        get { reals[1] }
        set { reals[1] = newValue }
    }
}

struct Kit_H027: HeroKit {
    let heroID = "H027"
    var isReady: Bool { true }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100 を近接スキルの射程に合わせて調整）

    enum Tune {
        // パッシブ
        static let flurryHits = 3
        static let flurryFlat = 80.0
        static let flurryAttackRatio = 0.30
        static let flurryHealFlat = 50.0
        static let flurryHealRatio = 0.20
        /// 竜気がたまる数。奥義中は 2。
        static let chargeNormal = 3
        static let chargeUlt = 2
        /// 三連突き中の射程の伸び（通常攻撃 150 → 約 208。MLBB の 1.8 → 2.5 の比）。
        static let flurryRangeBonus = 58.0
        static let rangeTag = "kit.H027.flurryRange"
        /// HP がこの割合未満の相手へ、通常攻撃・スキルのダメージが固定で +executeFlat。
        static let executeBelow = 0.5
        static let executeFlat = 30.0

        // S1 槍の跳ね上げ
        static let flipReach = 300.0
        static let flipAirborne = 0.8
        static let flipFlight = 0.7
        /// 放り投げた敵が着地する、術者の中心からの距離（背後）。
        static let flipLandingGap = 170.0
        /// 汎用 S1 のダメージに対する倍率（CD が汎用より長いぶんを補う。0.8〜1.3 の範囲内）。
        static let flipDamageRatio = 1.05

        // S2 竜牙の踏み込み
        static let strikeReach = 450.0
        static let strikeSpeed = 2400.0
        /// 到着時に対象がこれより離れていたら外れ（突進の追尾はしない）。
        static let strikeSlack = 260.0
        static let shredDuration = 2.0
        static let shredMinFlat = 15.0
        static let shredMaxFlat = 30.0
        static let shredTag = "kit.H027.shred"
        /// 直前に傷つけた敵が、この秒数以内に倒れたら S2 リセット。
        static let resetWindow = 0.5
        static let strikeDamageRatio = 1.10

        // 奥義 至高の武人
        static let ultDuration = 7.5
        static let ultMoveSpeed = 0.40
        static let ultAttackSpeed: [Double] = [0.35, 0.45, 0.55]
        static let ultMoveTag = "kit.H027.ult.move"
        static let ultAttackTag = "kit.H027.ult.attack"

        // クールダウン（MLBB 秒 → ランク間を線形補間 → Balance.Skills.cooldownScale を掛ける）
        static let flipCooldown = (12.0, 9.5)
        static let strikeCooldown = (12.0, 9.0)
        static let ultCooldown = (35.0, 27.0)
    }

    private enum Code {
        static let strikeArrive = 1
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        var t = base
        switch slot {
        case .skill1:
            // 対象指定（槍で跳ね上げる）。HUD・FX は cone の近接として扱い、shape で対象指定を示す
            t.aim = .unit
            t.range = Tune.flipReach
            t.radius = 150
            t.shape = .lockOn
            t.requiresTarget = true
        case .skill2:
            // 対象指定の突進（ブリンク系の archetype。突進の着地 AoE ゾーンは作らない）
            t = SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.strikeReach, radius: 150,
                               shape: .lockOn, requiresTarget: true)
        case .ultimate:
            // 自己強化（範囲・対象なし）。radius はボットが「近くに敵が居る」と数える目安と演出の大きさ
            t = SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: 350, shape: .selfRing)
        default:
            break
        }
        return t
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.hits = Tune.flurryHits
            n.damage = Self.flurryHitDamage(attack: stats.attack)
            n.heal = Self.flurryHeal(attack: stats.attack)
            n.damageType = .physical
            // 説明文に出す値は整数にそろえる（実際の値は damage / heal が持つ）
            n.extras = [KitStat(key: "flurryDamage", value: n.damage.rounded()),
                        KitStat(key: "flurryHeal", value: n.heal.rounded()),
                        KitStat(key: "executeFlat", value: Tune.executeFlat),
                        KitStat(key: "charge", value: Double(Tune.chargeNormal))]
        case .skill1:
            n.damage = base.damage * Tune.flipDamageRatio
            n.cooldown = Self.cooldown(Tune.flipCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .knockback
            n.ccDuration = Tune.flipAirborne
            n.extras = [KitStat(key: "airborne", value: Tune.flipAirborne),
                        KitStat(key: "executeFlat", value: Tune.executeFlat)]
        case .skill2:
            n.damage = base.damage * Tune.strikeDamageRatio
            n.cooldown = Self.cooldown(Tune.strikeCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.extras = [KitStat(key: "shred", value: Self.shredFlat(rank: rank, maxRank: slot.maxRank)),
                        KitStat(key: "shredDuration", value: Tune.shredDuration),
                        KitStat(key: "resetWindow", value: Tune.resetWindow)]
        case .ultimate:
            let r = min(max(1, rank), Tune.ultAttackSpeed.count)
            n.damage = 0
            n.hits = 1
            n.cc = .none
            n.ccIsUltimate = false
            n.ccDuration = 0
            // 汎用の連撃の被ダメ軽減は持たない（自己強化のみ）
            n.damageReduction = 0
            n.damageReductionDuration = 0
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "moveSpeed", value: Tune.ultMoveSpeed * 100),
                        KitStat(key: "attackSpeed", value: Tune.ultAttackSpeed[r - 1] * 100),
                        KitStat(key: "duration", value: Tune.ultDuration),
                        KitStat(key: "charge", value: Double(Tune.chargeUlt))]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "ダメージを与える（通常攻撃・スキル）たびに竜気が1たまる。{x3}たまると、次の通常攻撃が射程の伸びた「竜の三連突き」になり、{hits}回命中する。1回ごとに{x0}ダメージを与え、{x1}回復する。さらに、HPが半分未満の相手には、通常攻撃とスキルのダメージが常に+{x2}される。",
                en: "Each time you deal damage (basic attacks or skills) you gain a Dragon charge. At {x3} charges your next basic attack becomes a longer-ranged Dragon Flurry that hits {hits} times, dealing {x0} damage and healing {x1} per hit. Against enemies below 50% HP, your basic attacks and skills always deal +{x2} damage.")
        case .skill1:
            return KitText(
                ja: "対象の敵を槍で跳ね上げ、{damage}ダメージを与えて自分の背後へ放り投げる。対象は{x0}秒間打ち上げられて行動できない。クールダウン{cd}秒。",
                en: "Spear a target enemy into the air, dealing {damage} damage and flinging them behind you. The target is airborne for {x0}s and cannot act. Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "対象の敵へ一気に踏み込み、{damage}ダメージを与えて{x1}秒間防御を{x0}下げる。踏み込んだあとはそのまま通常攻撃に移る。敵を倒すと（直前に傷つけた敵が{x2}秒以内に倒れた場合も）クールダウンがリセットされる。",
                en: "Lunge at a target enemy, dealing {damage} damage and reducing their defense by {x0} for {x1}s, then follow up with a basic attack. Resets its cooldown whenever you kill an enemy (including one you damaged that dies within {x2}s).")
        case .ultimate:
            return KitText(
                ja: "スロウをすべて解除し、{x2}秒間 移動速度+{x0}%・攻撃速度+{x1}%、スロウ無効。この間は、竜気が{x3}たまるだけで三連突きが発動する。クールダウン{cd}秒。",
                en: "Remove all slows. For {x2}s gain +{x0}% movement speed and +{x1}% attack speed, and become immune to slows. During this time Dragon Flurry triggers after only {x3} charges. Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            let need = k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal
            return KitBadge(kind: .stacks, value: min(k.jarldCharge, need), maxValue: need)
        case .ultimate:
            guard k.jarldUltRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.jarldUltRemaining, total: Tune.ultDuration)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        switch slot {
        case .skill1, .skill2:
            // 対象指定: 射程内の敵が居なければ拒否（コスト・CD を消費しない）
            guard let u = Self.pickTarget(s, caster: caster, reach: targeting.reach, target: target) else {
                return .some(nil)
            }
            return .some(SkillAiming.aim(at: u, s, caster: caster, range: targeting.range,
                                         facing: Vec2.fromAngle(s.units[caster].facing)))
        case .ultimate:
            // 自己強化: 敵が居なくても撃てる
            let facing = Vec2.fromAngle(s.units[caster].facing)
            return .some(SkillAim(direction: facing, point: s.units[caster].pos, unit: nil, distance: 0))
        default:
            return nil
        }
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castFlip(&s, ctx, c)
        case .skill2: castStrike(&s, ctx, c)
        case .ultimate: castUltimate(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 敵を跳ね上げてダメージ → 打ち上げ → 自分の背後へ放り投げる。
    private func castFlip(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[t].pos, unit: t, shape: .lockOn,
                     duration: Tune.flipAirborne, count: 1)
        var p = Self.skillPayload(c, damage: c.numbers.damage + Self.executeBonus(s, t), effects:
                                  [.knockUp(duration: Tune.flipAirborne)])
        p.originPos = s.units[i].pos
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: s.units[i].team, targetIndex: t, payload: p,
                              from: s.units[i].pos)
        // 打ち上げが入った相手は、術者の頭上を越えて背後へ飛ぶ（CC 無効・構造物には動かない）
        guard CombatSystem.isLiving(s, t), s.units[t].has(.airborne), Kit.canDisplace(s, ctx, t) else { return }
        let from = s.units[t].pos
        let me = s.units[i].pos
        var dir = (me - from).normalized
        if dir == .zero { dir = -Vec2.fromAngle(s.units[i].facing) }
        MovementSystem.knockback(&s, ctx, unitIndex: t, direction: dir,
                                 distance: from.distance(to: me) + Tune.flipLandingGap, duration: Tune.flipFlight)
    }

    /// S2: 対象へ突進し、到着した tick に 1 度だけダメージ + 防御ダウン + 通常攻撃へ。
    private func castStrike(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let from = s.units[i].pos
        let toTarget = s.units[t].pos - from
        let dir = toTarget.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : toTarget.normalized
        // 対象の縁（術者の半径込み）で止まる
        let gap = s.units[i].radius + s.units[t].radius + 5
        let travel = min(Tune.strikeReach, max(0, toTarget.length - gap))
        let targetID = s.units[t].id
        s.units[i].hero!.kit!.jarldDashTargetID = targetID
        s.units[i].hero!.kit!.jarldDashDamage = c.numbers.damage
        s.units[i].hero!.kit!.jarldDashShred = Self.shredFlat(rank: c.numbers.rank, maxRank: c.slot.maxRank)
        // 経路上の敵には当たらない（affectsEnemies = false）。ハード CC の中断と着地の通知だけを使う
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.skill2), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * travel,
                                       speed: Tune.strikeSpeed, payload: carrier, radius: 0,
                                       arriveCode: Code.strikeArrive)
        Kit.emitCast(&s, c, origin: from, target: s.units[t].pos, unit: t, shape: .lockOn,
                     duration: from.distance(to: landing) / Tune.strikeSpeed, count: 1)
    }

    /// 奥義: スロウ解除 + 移動速度・攻撃速度 + 三連突きの必要回数を 2 に。
    private func castUltimate(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let rank = min(max(1, c.numbers.rank), Tune.ultAttackSpeed.count)
        let id = s.units[i].id
        s.units[i].statuses.removeAll { $0.kind == .slow }
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: Tune.ultDuration,
                                                                 magnitude: Tune.ultMoveSpeed, sourceID: id,
                                                                 tag: Tune.ultMoveTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .attackSpeedBoost, duration: Tune.ultDuration,
                                                                 magnitude: Tune.ultAttackSpeed[rank - 1],
                                                                 sourceID: id, tag: Tune.ultAttackTag))
        s.units[i].hero!.kit!.jarldUltRemaining = Tune.ultDuration
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing,
                     duration: Tune.ultDuration, count: Tune.chargeUlt)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard timer.code == Code.strikeArrive, let kit = s.units[owner].hero?.kit else { return }
        let targetID = kit.jarldDashTargetID
        s.units[owner].hero!.kit!.jarldDashTargetID = 0
        guard let t = s.index(of: targetID), CombatSystem.isLiving(s, t), !s.units[t].has(.untargetable),
              s.units[t].team != s.units[owner].team else { return }
        // 突進の間に対象が離れすぎていたら外れ
        let reach = s.units[owner].radius + s.units[t].radius + Tune.strikeSlack
        guard s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else { return }

        // 固定値の防御ダウンを、その時点の防御に対する割合へ換算（2 秒）
        let armor = max(1, s.units[t].stats.armor)
        let ratio = min(0.9, kit.jarldDashShred / armor)
        let shred = StatusEffect(kind: .armorShred, duration: Tune.shredDuration, magnitude: ratio,
                                 sourceID: s.units[owner].id, tag: Tune.shredTag)
        var p = HitPayload(damage: kit.jarldDashDamage + Self.executeBonus(s, t), damageType: .physical,
                           source: .skill(.skill2), statuses: [shred], skillID: Self.skillID(ctx, .skill2))
        p.originPos = s.units[owner].pos
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
        // 突進のあとはそのまま通常攻撃（調査資料: 未確認だが複数の解説が言及）
        if CombatSystem.isLiving(s, owner), CombatSystem.isLiving(s, t) {
            s.units[owner].attackTargetID = s.units[t].id
            s.units[owner].attackCooldown = 0
        }
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        // 三連突きの残り命中数は同じ tick の通常攻撃の中だけで使う（対象が途中で倒れた分を持ち越さない）
        if k.jarldFlurryHitsLeft != 0 { s.units[owner].hero!.kit!.jarldFlurryHitsLeft = 0 }

        // 奥義中: スロウ無効
        if k.jarldUltRemaining > 0, s.units[owner].has(.slow) {
            s.units[owner].statuses.removeAll { $0.kind == .slow }
        }

        // 三連突きの準備ができている間は射程が伸びる（0.5 秒の状態を短くなったら更新し、イベントを出し続けない）
        let need = k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal
        if k.jarldCharge >= need {
            let left = s.units[owner].statuses.first { $0.kind == .attackRangeBoost && $0.tag == Tune.rangeTag }?.remaining
            if left == nil || left! < 0.2 {
                Kit.grantAttackRange(&s, target: owner, amount: Tune.flurryRangeBonus, duration: 0.5, tag: Tune.rangeTag)
            }
        }

        // 直前に傷つけた敵が 0.5 秒以内に倒れたら S2 のクールダウンをリセット
        if k.jarldWatchedID != 0 {
            if k.jarldResetWindow <= 0 {
                s.units[owner].hero!.kit!.jarldWatchedID = 0
            } else if Self.isDead(s, k.jarldWatchedID) {
                s.units[owner].hero!.kit!.jarldWatchedID = 0
                s.units[owner].hero!.kit!.jarldResetWindow = 0
                Kit.setCooldown(&s, ctx, caster: owner, slot: .skill2, seconds: 0)
            }
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 突進中のハード CC: 到着処理が呼ばれないので突進先の記録だけ捨てる
        s.units[owner].hero?.kit?.jarldDashTargetID = 0
    }

    // MARK: - C. パッシブ

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard let k = s.units[attacker].hero?.kit else { return }
        let flat = Self.executeBonus(s, target)
        let need = k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal
        guard k.jarldCharge >= need else {
            plan.payload.damage += flat
            return
        }
        // 三連突き: 同じ対象へ 3 回（同 tick）。1 撃 80 + 攻撃力 30%、命中ごとに 50 + 20% 回復
        let attack = s.units[attacker].stats.attack
        let crit = plan.payload.isCrit ? max(1, s.units[attacker].stats.critMultiplier) : 1
        var hit = plan.payload
        hit.damage = Self.flurryHitDamage(attack: attack) * crit + flat
        hit.effects = [.healOwner(flat: Self.flurryHeal(attack: attack), ratioOfDealt: 0)]
        plan.payload = hit
        plan.extras.append(contentsOf: Array(repeating: hit, count: Tune.flurryHits - 1))
        s.units[attacker].hero!.kit!.jarldCharge = 0
        s.units[attacker].hero!.kit!.jarldFlurryHitsLeft = Tune.flurryHits
        s.units[attacker].statuses.removeAll { $0.kind == .attackRangeBoost && $0.tag == Tune.rangeTag }
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        guard let k = s.units[attacker].hero?.kit else { return }
        if k.jarldFlurryHitsLeft > 0 {
            // 三連突きの命中は竜気を増やさない（リセット済み）
            s.units[attacker].hero!.kit!.jarldFlurryHitsLeft = k.jarldFlurryHitsLeft - 1
        } else {
            gainCharge(&s, attacker)
        }
        watch(&s, attacker, target)
    }

    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double) {
        // 「ダメージを与えた」ときだけ（CC のみの命中は数えない）
        guard damage > 0, s.units[attacker].hero?.kit != nil else { return }
        gainCharge(&s, attacker)
        watch(&s, attacker, target)
    }

    func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero: Int, victim: Int) {
        // キル（止めを刺したのが自分）で S2 リセット。アシストでは戻らない
        guard s.units[victim].lastAttackerID == s.units[hero].id else { return }
        Kit.setCooldown(&s, ctx, caster: hero, slot: .skill2, seconds: 0)
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        switch slot {
        case .ultimate:
            // 追撃・交戦の強化: 交戦中で、敵が近い間に使う
            guard fighting, s.units[bot].pos.distance(to: s.units[target].pos) <= 700 else { return .skip }
            return .cast(.none)
        default:
            return .useDefault
        }
    }

    // MARK: - 部品

    private func gainCharge(_ s: inout SimState, _ i: Int) {
        let need = (s.units[i].hero?.kit?.jarldUltRemaining ?? 0) > 0 ? Tune.chargeUlt : Tune.chargeNormal
        let n = s.units[i].hero?.kit?.jarldCharge ?? 0
        s.units[i].hero?.kit?.jarldCharge = min(need, n + 1)
    }

    /// 直前に傷つけた敵を覚える（0.5 秒以内に倒れたら S2 リセット）。構造物は除く。
    private func watch(_ s: inout SimState, _ i: Int, _ t: Int) {
        guard s.units.indices.contains(t), !s.units[t].isStructure else { return }
        let id = s.units[t].id
        s.units[i].hero?.kit?.jarldWatchedID = id
        s.units[i].hero?.kit?.jarldResetWindow = Tune.resetWindow
    }

    static func isDead(_ s: SimState, _ id: EntityID) -> Bool {
        guard let t = s.index(of: id) else { return true }
        return !s.units[t].isAlive || s.units[t].hero?.isDead == true
    }

    /// 相手の HP が半分未満なら固定で +30。
    static func executeBonus(_ s: SimState, _ t: Int) -> Double {
        guard s.units.indices.contains(t), !s.units[t].isStructure, s.units[t].hpRatio < Tune.executeBelow else { return 0 }
        return Tune.executeFlat
    }

    static func flurryHitDamage(attack: Double) -> Double { Tune.flurryFlat + Tune.flurryAttackRatio * attack }
    static func flurryHeal(attack: Double) -> Double { Tune.flurryHealFlat + Tune.flurryHealRatio * attack }

    /// 防御ダウン量（固定値 15 → 30 をランクで線形に）。
    static func shredFlat(rank: Int, maxRank: Int) -> Double {
        lerp(Tune.shredMinFlat, Tune.shredMaxFlat, rank: rank, maxRank: maxRank)
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、Velstria の全体倍率と CD 短縮を掛ける。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        let sec = lerp(range.0, range.1, rank: rank, maxRank: maxRank)
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    private static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H027", slot: slot)?.skillID
    }

    private static func skillPayload(_ c: KitCast, damage: Double, effects: [HitEffect]) -> HitPayload {
        HitPayload(damage: damage, damageType: c.numbers.damageType, source: .skill(c.slot),
                   skillID: c.check.skill.skillID, effects: effects)
    }

    /// 対象指定の選び方: 指定ユニット → 指定地点に近い敵 → 向きに近い敵 → 自動（ヒーロー優先で HP + シールド最小）。
    /// すべて「術者の中心から対象の縁まで reach 以内」の視認中の敵（構造物・無敵・対象不可を除く）。
    static func pickTarget(_ s: SimState, caster i: Int, reach: Double, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func inReach(_ j: Int) -> Bool {
            guard j != i, !s.units[j].isStructure, s.isTargetableEnemy(j, of: team),
                  !s.units[j].has(.invulnerable) else { return false }
            let r = reach + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), inReach(j) { return j }

        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where inReach(j) {
            let hero = s.units[j].kind == .hero
            var key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d):
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(d.normalized) / len : 1
                key = (1 - cosine) * 1e7 + len
            case .unit, .none:
                key = hero ? max(0, s.units[j].hp) + s.units[j].totalShield : s.units[j].pos.distanceSquared(to: pos)
            }
            // ヒーローを先に（同じ基準の中で）
            if !hero { key += 1e12 }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }
}
