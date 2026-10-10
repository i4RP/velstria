import Foundation

// 担当: kit-H030（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Layla.md）
// H030 星砲のライナ = MLBB ライラの Velstria 版（レンジャー・遠隔 550・マナ）。
// 遠距離ほど火力が伸びる砲撃手。パッシブは距離補正（通常攻撃・スキル。タワーには効かない）、
// スキル1（遠星弾）は会心のある直線弾（命中で射程延長と加速）、スキル2（星爆弾）は爆発する星環弾（誰にも当たらなくても射程の端で
// 爆発し、軽い減速と刻印を付ける。刻印へ当てると弾けて周囲をスタン）、アルティメット（星砕の大砲）は短い溜めの後に画面を貫く貫通ビーム。
// アルティメットのランクごとに通常攻撃と星環弾の射程が常に伸びる。
// 対応表は docs/kits/Layla.md の「Velstria 実装対応表」。

/// ライナの調整値（docs/kits/Layla.md の数値を Velstria の単位・TTK に合わせたもの）。
enum RainaTuning {
    // MARK: パッシブ（遠星の照準）
    /// 補正が最大になる距離（Velstria 単位）。ライラの 6 マス（基本射程 4.3）を、ライナの基本射程 550 に合わせて伸ばした値。
    /// 基本射程の端では約 +25%、射程延長を重ねて初めて頭打ちの +30% に届く。
    static let farDistance: Double = 770
    /// 遠隔の基本射程（通常攻撃。説明文で「射程の何倍」と書くための値）。
    static let baseRange: Double = 550
    static let maxDistanceBonus: Double = 0.30
    static let distanceScaling = DamageScaling.distance(near: 0, far: farDistance, minMult: 1,
                                                        maxMult: 1 + maxDistanceBonus)

    // MARK: 射程
    /// 奥義 1 ランクごとの通常攻撃・星環弾の射程の常時延長（ライラ: +0.6 マス/ランク）。
    static let ultRangePerRank: Double = 60
    /// S1 命中時の一時的な射程延長（奥義ランク 0〜3。ライラ: +1.6 / 1.4 / 1.2 / 1.0 マス）。
    static let s1RangeBuff: [Double] = [160, 140, 120, 100]
    static let s1RangeBuffDuration: Double = 3
    /// 常時延長のステータスに持たせる持続（実質無期限）。
    static let permanent: Double = 1_000_000

    // MARK: S1（マレフィック・ボム）
    static let s1Ratio: Double = 0.92
    /// 命中時の加速（+60%、1.2 秒かけて 0 へ。敵ヒーローに当たると持続が倍）。
    static let rushSpeed: Double = 0.6
    static let rushDuration: Double = 1.2
    static let rushHeroDuration: Double = 2.4

    // MARK: S2（ヴォイド・プロジェクタイル）
    /// 汎用の遠隔 S2 は「ブリンク + 強化攻撃」で数値が半分になっているため、基準は元のスキル値（base ÷ empowerRatio）。
    static let s2PrimaryRatio: Double = 0.70
    static let s2DetonationRatio: Double = 0.40
    static let s2Speed: Double = 1500
    static let s2Width: Double = 60
    /// 爆発に付く軽い減速（元のスキルに減速の記載はあるが数値は無い。タグ付きの 30% を 1 秒）。
    static let orbSlow: Double = 0.30
    static let orbSlowDuration: Double = 1.0
    /// 射程の端で消える瞬間に爆発させる予約の余裕（弾が消えた次の tick 以降に爆発させる）。
    static let orbEndLag: Double = Balance.dt
    /// 爆発と刻印の弾けの半径は同じ（スキル定義の radius）。
    static let markDuration: Double = 3
    static let markStun: Double = 0.25

    // MARK: 奥義（デストラクション・ラッシュ）
    static let ultRatio: Double = 1.0
    /// 溜め（0.3 → 0.2 秒）とビームの速さ（3600 → 7000）。弾は 1 tick の区間を線分で掃引して当てる（ProjectileSystem.stepLinear）ので
    /// 7000（1 tick = 約 233）でもすり抜けない。射程 2000 を約 0.29 秒で貫くので、動く相手にも「撃った瞬間」に近く当たる。
    static let ultWindup: Double = 0.2
    static let ultBeamSpeed: Double = 7000

    // MARK: クールダウン（MLBB の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
    /// ライラ: S1 6.0 → 4.0 / S2 7.5 → 6.5 / 奥義 37 / 32 / 27 秒（以前はマスターの CD 6.5 / 7.6 / 33 秒のままだった）。
    static let s1Cooldown = (6.0, 4.0)
    static let s2Cooldown = (7.5, 6.5)
    static let ultCooldown = (37.0, 27.0)

    // MARK: タグ・コード
    static let ultRangeTag = KitTags.buff("H030", "ultRange")
    static let s1RangeTag = KitTags.buff("H030", "s1Range")
    static let rushTag = KitTags.buff("H030", "rush")
    static let markStunTag = KitTags.buff("H030", "markStun")
    static let orbSlowTag = KitTags.buff("H030", "orbSlow")
    static let markName = "void"

    /// HitPayload.kitEvent
    enum Event {
        static let bomb = 1
        static let orb = 2
        static let beam = 3
    }

    /// KitTimer.code
    enum Code {
        static let beam = 1
        /// 星環弾が何にも当たらずに射程の端へ着いた: その場で爆発する（当たったら onHit が取り消す）。
        static let orbEnd = 2
    }
}

extension KitState {
    /// S1 の射程延長の残り秒（HUD のバッジ用）。
    var rainaRangeBuff: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    /// S2 を撃った位置（爆発の距離補正の起点）。
    var rainaOrbOrigin: Vec2 {
        get { Vec2(reals[0], reals[1]) }
        set {
            reals[0] = newValue.x
            reals[1] = newValue.y
        }
    }

    /// 刻印が弾けた回数（検証用）。
    var rainaDetonations: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }
}

struct Kit_H030: HeroKit {
    let heroID = "H030"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H030(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    typealias T = RainaTuning

    // MARK: A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 汎用の遠隔直線弾のまま（射程 650・弾幅は半径の半分）
            return base
        case .skill2:
            // 星環弾: 直線に飛んで最初の敵で爆発する。radius は弾の半幅（爆発の半径は numbers の extras）
            return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: skill.range, radius: T.s2Width)
        case .ultimate:
            var t = base
            t.shape = .wideLine
            return t
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.extras = [KitStat(key: "maxBonus", value: T.maxDistanceBonus * 100),
                        KitStat(key: "rangePerRank", value: T.ultRangePerRank),
                        KitStat(key: "farDistance", value: T.farDistance)]
        case .skill1:
            n.damage = base.damage * T.s1Ratio
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "rangeBuff", value: T.s1RangeBuff[0]),
                        KitStat(key: "rangeBuffDuration", value: T.s1RangeBuffDuration),
                        KitStat(key: "rushPercent", value: T.rushSpeed * 100),
                        KitStat(key: "rushDuration", value: T.rushDuration),
                        KitStat(key: "rangeBuffMin", value: T.s1RangeBuff[T.s1RangeBuff.count - 1])]
        case .skill2:
            let raw = base.damage / Balance.Skills.empowerRatio
            n.damage = raw * T.s2PrimaryRatio
            n.cooldown = Self.cooldown(T.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccDuration = T.orbSlowDuration
            n.extras = [KitStat(key: "detonation", value: raw * T.s2DetonationRatio),
                        KitStat(key: "markDuration", value: T.markDuration),
                        KitStat(key: "markStun", value: T.markStun),
                        KitStat(key: "blastRadius", value: skill.radius),
                        KitStat(key: "slow", value: T.orbSlow * 100),
                        KitStat(key: "slowDuration", value: T.orbSlowDuration)]
        case .ultimate:
            n.damage = base.damage * T.ultRatio
            n.cooldown = Self.cooldown(T.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "rangePerRank", value: T.ultRangePerRank),
                        KitStat(key: "windup", value: T.ultWindup)]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        // 距離の単位: 通常攻撃の基本射程（\(Int(T.baseRange))）に対する倍率で示す
        let farMult = String(format: "%.1f", T.farDistance / T.baseRange)
        let edgeBonus = Int((T.maxDistanceBonus * T.baseRange / T.farDistance * 100).rounded())
        switch slot {
        case .passive:
            return KitText(
                ja: "遠くの敵ほど与ダメージが増える（通常攻撃とスキル。タワーには効かない）。基本射程の端（\(Int(T.baseRange))）で約+\(edgeBonus)%、"
                    + "基本射程の\(farMult)倍（距離{farDistance}）で最大+{maxBonus}%。アルティメットのランクが上がるごとに、"
                    + "通常攻撃と星爆弾の射程が常に{rangePerRank}伸びる。",
                en: "Deals more damage the farther the target is (basic attacks and skills; not against turrets): about +\(edgeBonus)% at "
                    + "the edge of the basic range (\(Int(T.baseRange))), up to +{maxBonus}% at \(farMult)x the basic range (distance "
                    + "{farDistance}). Each Ultimate rank permanently adds {rangePerRank} range to basic attacks and Starburst Shell.")
        case .skill1:
            return KitText(
                ja: "指定方向へ砲弾を撃ち、最初に当たった敵に{damage}の物理ダメージ（会心あり）。"
                    + "命中すると{rangeBuffDuration}秒間、通常攻撃と星爆弾の射程が最大{rangeBuff}伸び（アルティメットのランクが上がるほど小さくなり、"
                    + "最大ランクで{rangeBuffMin}）、移動速度が{rushPercent}%上がって{rushDuration}秒かけて元に戻る（敵ヒーローに当たると加速の持続が倍）。",
                en: "Fires a shell that deals {damage} physical damage to the first enemy hit (can crit). On hit, basic attacks and "
                    + "Starburst Shell gain up to {rangeBuff} range for {rangeBuffDuration}s (smaller as the Ultimate ranks up, down to "
                    + "{rangeBuffMin} at max rank), and Raina gains {rushPercent}% movement speed that fades over {rushDuration}s "
                    + "(doubled when an enemy hero is hit).")
        case .skill2:
            return KitText(
                ja: "光球を撃ち、最初に当たった敵の位置で爆発する（何にも当たらなければ射程の端で爆発）。半径{blastRadius}の敵に"
                    + "{damage}の物理ダメージと{slow}%の減速（{slowDuration}秒）を与え、{markDuration}秒間の刻印を付ける。"
                    + "刻印した敵に通常攻撃・スキル1・アルティメットが当たると刻印が弾け、周囲の敵に{detonation}の物理ダメージと{markStun}秒のスタン。",
                en: "Fires an orb that bursts on the first enemy hit (or at the end of its range if nothing is hit): {damage} "
                    + "physical damage and a {slow}% slow for {slowDuration}s to enemies within {blastRadius}, and marks them for "
                    + "{markDuration}s. When a basic attack, Skill 1 or the Ultimate hits a marked enemy, the mark pops for "
                    + "{detonation} physical damage and a {markStun}s stun to nearby enemies.")
        case .ultimate:
            return KitText(
                ja: "{windup}秒溜めて、指定方向へ射程{range}の貫通ビームを放つ（ビームは一瞬で届く）。ビーム上の全ての敵に{damage}の物理ダメージ。"
                    + "ランクが上がるごとに、通常攻撃と星爆弾の射程が常に{rangePerRank}伸びる。",
                en: "After a {windup}s charge, fires a piercing beam of {range} range that travels almost instantly and deals "
                    + "{damage} physical damage to every enemy in its path. Each rank permanently adds {rangePerRank} range to "
                    + "basic attacks and Starburst Shell.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard slot == .skill1, let k = hero.kit, k.rainaRangeBuff > 0 else { return nil }
        return KitBadge(kind: .timer, remaining: k.rainaRangeBuff, total: T.s1RangeBuffDuration)
    }

    // MARK: B. 実行

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        let i = c.caster
        switch c.slot {
        case .skill1:
            castBomb(&s, c)
        case .skill2:
            castOrb(&s, ctx, c)
        case .ultimate:
            // 溜め（連打・スタンで途切れる）の後にビームを放つ。向きは発動時に固定
            Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * c.targeting.range, unit: c.aim.unit,
                         shape: .wideLine, duration: T.ultWindup, count: 1)
            Kit.schedule(&s, caster: i, slot: .ultimate, code: T.Code.beam, after: T.ultWindup, point: c.aim.direction)
        case .passive:
            break
        }
        return .done
    }

    /// S1: 直線弾。最初に当たった敵へ（会心あり・距離補正）。命中で射程延長と加速。
    private func castBomb(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        var p = HitPayload(damage: c.numbers.damage, damageType: c.check.skill.damageType, source: .skill(.skill1),
                           skillID: c.check.skill.skillID, scaling: T.distanceScaling, originPos: s.units[i].pos,
                           kitEvent: T.Event.bomb)
        if Self.rollCrit(&s, i) {
            p.isCrit = true
            p.damage *= max(1, s.units[i].stats.critMultiplier)
        }
        Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * c.targeting.range, unit: c.aim.unit, count: 1)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: c.aim.direction, maxDistance: c.targeting.range),
                               speed: Balance.Skills.skillshotSpeed, width: c.targeting.radius, pierce: false,
                               payload: p, visual: c.check.skill.effectID)
    }

    /// S2: 星環弾。奥義ランクの常時延長と S1 の一時延長ぶん遠くへ届く。最初に当たった敵の位置で爆発する（onHit）。
    /// 何にも当たらなければ射程の端で爆発する（予約タイマー。当たったら onHit が取り消すので 1 回だけ爆発する）。
    private func castOrb(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let range = c.targeting.range + Self.rangeBonus(s, i)
        let p = HitPayload(damage: 0, damageType: c.check.skill.damageType, source: .skill(.skill2),
                           skillID: c.check.skill.skillID, kitEvent: T.Event.orb)
        let here = s.units[i].pos
        s.units[i].hero?.kit?.rainaOrbOrigin = here
        var shown = c
        shown.targeting.range = range
        Kit.emitCast(&s, shown, target: s.units[i].pos + c.aim.direction * range, unit: c.aim.unit,
                     duration: range / T.s2Speed, count: 1)
        let orb = ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: c.aim.direction, maxDistance: range),
                                         speed: T.s2Speed, width: T.s2Width, pierce: false, payload: p,
                                         visual: c.check.skill.effectID)
        // マップの端で止まるときはそこまでの距離で数える（弾が消える位置 = 爆発の位置）
        let dir = c.aim.direction.normalized
        let edge = ProjectileSystem.distanceToMapEdge(from: here, direction: dir, size: ctx.map.size)
        let flight = min(range, edge)
        Kit.schedule(&s, caster: i, slot: .skill2, code: T.Code.orbEnd, after: flight / T.s2Speed + T.orbEndLag,
                     targetID: orb, point: here + dir * flight, interruptible: false)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        switch timer.code {
        case T.Code.beam:
            fireBeam(&s, ctx, owner: owner, direction: timer.point)
        case T.Code.orbEnd:
            // 弾は何にも当たらず消えた（当たっていれば onHit が予約を取り消している）: 射程の端で爆発する
            explode(&s, ctx, owner: owner, center: timer.point)
        default:
            break
        }
    }

    /// 奥義: ライン上の全ての敵に（距離補正）。貫通する高速の弾でビームを表す。
    private func fireBeam(_ s: inout SimState, _ ctx: SimContext, owner i: Int, direction: Vec2) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .ultimate),
              let def = ctx.master.hero(skill.heroID) else { return }
        let t = HeroKits.targeting(for: skill, hero: def, stage: 0)
        let dir = direction.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : direction.normalized
        let p = HitPayload(damage: n.damage, damageType: skill.damageType, source: .skill(.ultimate),
                           ccIsUltimate: true, skillID: skill.skillID, scaling: T.distanceScaling,
                           originPos: s.units[i].pos, kitEvent: T.Event.beam)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: t.range),
                               speed: T.ultBeamSpeed, width: t.radius, pierce: true, payload: p, visual: skill.effectID)
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        switch event {
        case T.Event.bomb:
            bombLanded(&s, owner: owner, target: target)
            detonate(&s, ctx, owner: owner, target: target)
        case T.Event.orb:
            // 当たった: 射程の端の爆発の予約は要らない
            Kit.cancelScheduled(&s, caster: owner, code: T.Code.orbEnd)
            explode(&s, ctx, owner: owner, center: s.units[target].pos)
        case T.Event.beam:
            detonate(&s, ctx, owner: owner, target: target)
        default:
            break
        }
    }

    /// S1 命中: 射程延長（奥義ランクが高いほど一時延長は小さい）と加速（敵ヒーローなら持続が倍）。
    private func bombLanded(_ s: inout SimState, owner i: Int, target t: Int) {
        guard CombatSystem.isLiving(s, i) else { return }
        let ultRank = min(max(0, s.units[i].hero?.rank(.ultimate) ?? 0), T.s1RangeBuff.count - 1)
        Kit.grantAttackRange(&s, target: i, amount: T.s1RangeBuff[ultRank], duration: T.s1RangeBuffDuration,
                             tag: T.s1RangeTag)
        s.units[i].hero?.kit?.rainaRangeBuff = T.s1RangeBuffDuration
        let duration = s.units[t].kind == .hero ? T.rushHeroDuration : T.rushDuration
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: duration,
                                                                magnitude: T.rushSpeed, sourceID: s.units[i].id,
                                                                tag: T.rushTag))
    }

    /// S2 の爆発（命中した敵の位置、または射程の端）: 半径内の全ての敵に距離補正つきのダメージ + 軽い減速 + 刻印。
    private func explode(_ s: inout SimState, _ ctx: SimContext, owner i: Int, center: Vec2) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .skill2) else { return }   // 放たれた弾は術者が倒れても爆発する
        let origin = s.units[i].hero?.kit?.rainaOrbOrigin ?? s.units[i].pos
        let slow = StatusEffect(kind: .slow, duration: T.orbSlowDuration, magnitude: T.orbSlow, sourceID: s.units[i].id,
                                tag: T.orbSlowTag)
        let p = HitPayload(damage: n.damage, damageType: skill.damageType, source: .skill(.skill2), statuses: [slow],
                           skillID: skill.skillID,
                           effects: [.addMark(name: T.markName, stacks: 1, maxStacks: 1, duration: T.markDuration)],
                           scaling: T.distanceScaling, originPos: origin)
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: center, radius: skill.radius, shape: .circle, payload: p)
    }

    /// 刻印が付いた敵に通常攻撃・S1・奥義が当たったら、刻印を消費して周囲に爆発とスタン（予告なしのゾーンで演出も出す）。
    private func detonate(_ s: inout SimState, _ ctx: SimContext, owner i: Int, target t: Int) {
        guard s.units.indices.contains(t), CombatSystem.isLiving(s, i), CombatSystem.isLiving(s, t) else { return }
        let tag = KitTags.mark("H030", T.markName, owner: s.units[i].id)
        guard Kit.markStacks(s, target: t, tag: tag) > 0, let (skill, n) = Self.numbersNow(s, ctx, i, .skill2),
              let damage = n.extras.first(where: { $0.key == "detonation" })?.value else { return }
        Kit.consumeMarks(&s, target: t, tag: tag)
        s.units[i].hero?.kit?.rainaDetonations += 1
        let stun = StatusEffect(kind: .stun, duration: T.markStun, sourceID: s.units[i].id, tag: T.markStunTag)
        let p = HitPayload(damage: damage, damageType: skill.damageType, source: .skill(.skill2), statuses: [stun],
                           skillID: skill.skillID, scaling: T.distanceScaling, originPos: s.units[i].pos)
        ZoneSystem.spawn(&s, ownerIndex: i, center: s.units[t].pos, radius: skill.radius, delay: 0, payload: p,
                         visual: skill.effectID)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        // 奥義ランクの常時射程延長（ステータスで持つ。ランクが上がれば大きさだけ更新）
        let want = T.ultRangePerRank * Double(s.units[i].hero?.rank(.ultimate) ?? 0)
        if let k = s.units[i].statuses.firstIndex(where: { $0.kind == .attackRangeBoost && $0.tag == T.ultRangeTag }) {
            if want <= 0 {
                s.units[i].statuses.remove(at: k)
            } else if s.units[i].statuses[k].magnitude != want {
                s.units[i].statuses[k].magnitude = want
            }
        } else if want > 0 {
            Kit.grantAttackRange(&s, target: i, amount: want, duration: T.permanent, tag: T.ultRangeTag)
        }
        // 加速は 1.2 秒かけて 0 へ（持続が倍のときは最初の 1.2 秒は維持）
        if let k = s.units[i].statuses.firstIndex(where: { $0.kind == .speedBoost && $0.tag == T.rushTag }) {
            let left = max(0, s.units[i].statuses[k].remaining)
            s.units[i].statuses[k].magnitude = T.rushSpeed * min(1, left / T.rushDuration)
        }
    }

    // MARK: C. パッシブ（遠星の照準）

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        // タワーには効かない。弾の発射位置を起点に、命中時の距離で補正する
        guard !s.units[target].isStructure else { return }
        plan.payload.scaling = T.distanceScaling
        plan.payload.originPos = s.units[attacker].pos
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        detonate(&s, ctx, owner: attacker, target: target)
    }

    // MARK: D. ボット

    /// アルティメットの狙い: 相手の動きを先読みする。ビームは発動の 0.2 秒後（溜め）に速さ 7000 で飛ぶので、
    /// 到達までの時間は 溜め + 距離 ÷ 速さ。汎用の見積もり（0.1 + 距離 ÷ 1600）はビームより長いので使わない。
    /// 先読みの強さは難易度の精度（乱数を引かない = botCast は状態を変えない）。撃つ判断は汎用の関門（倒せる / 2 体以上）のまま。
    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting, target: Int,
                 fighting: Bool) -> BotKitDecision {
        guard slot == .ultimate, s.units.indices.contains(target), s.units.indices.contains(bot) else { return .useDefault }
        let me = s.units[bot].pos
        let foe = s.units[target]
        let dist = me.distance(to: foe.pos)
        guard dist <= targeting.range + foe.radius else { return .skip }
        let accuracy = BotProfile.of(s.units[bot].hero?.botDifficulty ?? .normal).accuracy
        let travel = T.ultWindup + dist / T.ultBeamSpeed
        let velocity = Self.observedVelocity(s, bot: bot, target: target)
        let leadSeconds = travel * accuracy
        let lead = Vec2(velocity.x * leadSeconds, velocity.y * leadSeconds)
        let direction = (foe.pos + lead - me).normalized
        return direction == .zero ? .skip : .cast(.direction(direction))
    }

    // MARK: ヘルパー

    /// ボットのチームが観測している敵ヒーローの移動速度（ユニット/秒）。見えていない・観測できなければ 0。
    static func observedVelocity(_ s: SimState, bot: Int, target: Int) -> Vec2 {
        let team = s.units[bot].team.rawValue
        guard s.bots.teams.indices.contains(team) else { return .zero }
        let intel = s.bots.teams[team]
        guard let k = intel.enemyIDs.firstIndex(of: s.units[target].id), intel.velocity.indices.contains(k) else {
            return .zero
        }
        return intel.velocity[k]
    }

    /// 通常攻撃と星環弾の現在の射程延長（奥義ランクの常時延長 + S1 の一時延長）。
    static func rangeBonus(_ s: SimState, _ i: Int) -> Double {
        var bonus = 0.0
        for st in s.units[i].statuses where st.kind == .attackRangeBoost
            && (st.tag == T.ultRangeTag || st.tag == T.s1RangeTag) {
            bonus += st.magnitude
        }
        return bonus
    }

    /// 現在のランク・能力値でのスキルと数値。
    static func numbersNow(_ s: SimState, _ ctx: SimContext, _ i: Int, _ slot: SkillSlot) -> (SkillDef, SkillNumbers)? {
        guard let h = s.units[i].hero, let def = ctx.master.hero(h.heroID),
              let skill = ctx.master.skill(hero: h.heroID, slot: slot) else { return nil }
        return (skill, SkillCatalog.numbers(for: skill, hero: def, rank: max(1, h.rank(slot)), stats: s.units[i].stats))
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、CD 短縮を掛ける（全体倍率 cooldownScale は 1.0 = MLBB の秒数のまま）。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        var sec = range.0
        if maxRank > 1 {
            let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
            sec = range.0 + (range.1 - range.0) * t
        }
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    /// 会心の判定（通常攻撃と同じ。確率が 0 のときは乱数を引かない）。
    static func rollCrit(_ s: inout SimState, _ i: Int) -> Bool {
        let chance = s.units[i].stats.critChance
        if chance >= 1 { return true }
        return chance > 0 && s.rng.nextDouble() < chance
    }
}
