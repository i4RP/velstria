import Foundation

// 担当: kit-H029（docs/SKILL_KITS.md / docs/NEW_HEROES.md）
// H029 聖槌のボルグ = Velstria 版の Tigreal（MLBB。調査: docs/kits/Tigreal.md、対応表: 同ファイル末尾）。
// サポート（ローム）の近接タンク。キットはロールの汎用パッシブ（味方回復）と汎用奥義（味方全体回復）を置き換える。
//   パッシブ 聖鎚の誓い        — スキルを使う / 通常攻撃（タワー・ジャングルの敵を含む。ミニオンは除く）を受けるたびに「誓い」+1。
//                               4 つで次に受ける通常攻撃のダメージを無効化して誓いが消える（Fearless）。無効化の瞬間は
//                               自分に 0.3 秒の「blocked」の印（.mark）が付き、パッシブのバッジが 0.3 秒だけタイマーになる（App の演出の合図）。
//   スキル1 聖槌波             — 前方の扇に衝撃波を 3 回。扇の半径が射程の 0.7 → 0.85 → 1.0 倍と前へ広がる（近くの敵ほど多く当たる）。
//                               1 回ごとにダメージ + 鈍足（20 → 40 → 60%、1.5 秒。命中ごとに深まる）。
//   スキル2 聖槌突撃           — 突進して通り道の敵にダメージ、突進の終点まで押し運ぶ。4 秒以内の再使用（同じ castSkill）で
//                               前方の敵にダメージ + 打ち上げ。再使用の窓が閉じてからクールダウンを数える。
//   アルティメット 崩落聖域（Implosion） — 詠唱 0.8 秒。最初の 0.3 秒は CC（スタン・打ち上げ・suppress）で、その後は suppress だけで中断される。
//                               0.3 秒で周囲の敵を引き寄せ（0.38 秒かけて集める）、0.8 秒でダメージ + スタン 1.8 秒。
//
// 状態（KitState）:
//   ints[0]  = 誓い（0..4。4 = 無効化の準備完了）      ints[1] = 奥義の段（0 = なし / 1 = 溜め / 2 = 引き寄せ後）
//   ints[2]  = 無効化した回数（累計。検証用）          ints[3] = 直近の引き寄せで動かせた敵の数（検証用）
//   timers[0] = 誓いが消えるまでの秒                   timers[1] = 奥義の詠唱の残り秒（HUD 用）
//   timers[2] = 無効化の演出の残り秒（0.3 秒。バッジをタイマーにする）
//   reals[0..1] = S1 / S2 の方向    reals[2..3] = S2 の突進の終点    reals[4..5] = S2 再使用の方向

extension KitState {
    var borgVow: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var borgUltPhase: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var borgBlocks: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var borgPulled: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var borgVowTimer: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var borgChannel: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var borgBlockFlash: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    var borgAim: Vec2 {
        get { Vec2(reals[0], reals[1]) }
        set {
            reals[0] = newValue.x
            reals[1] = newValue.y
        }
    }

    var borgDashEnd: Vec2 {
        get { Vec2(reals[2], reals[3]) }
        set {
            reals[2] = newValue.x
            reals[3] = newValue.y
        }
    }

    var borgSmashDir: Vec2 {
        get { Vec2(reals[4], reals[5]) }
        set {
            reals[4] = newValue.x
            reals[5] = newValue.y
        }
    }
}

struct Kit_H029: HeroKit {
    let heroID = "H029"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H029(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100 を近接スキルの射程に合わせて調整）

    enum Tune {
        // パッシブ 聖鎚の誓い
        /// 無効化が準備できる誓いの数。
        static let vowStacks = 4
        /// 誓いが（新しく増えないまま）消えるまでの秒。調査に「不明」とある値なので選んだ値。
        static let vowExpire = 8.0
        /// 無効化の合図（自分への「blocked」の印 + パッシブのバッジのタイマー）の長さ。App の演出がこれを見て盾の弾けを出す。
        static let blockFlash = 0.3
        static let blockMark = "blocked"

        // スキル1 聖槌波
        static let waveReach = 300.0
        static let waveHalfAngle = Balance.Skills.coneHalfAngle
        static let waveCount = 3
        /// 衝撃波が前へ進んで見えるよう、波ごとの扇の半径（射程に対する比。1 回目 → 3 回目）。近くの敵ほど多くの波に当たり、鈍足が深まる。
        static let waveRadiusScale: [Double] = [0.7, 0.85, 1.0]
        static let waveFirstDelay = 0.12
        static let waveInterval = 0.2
        /// 命中 1 回ごとの鈍足（20 → 40 → 60%）。
        static let waveSlowPerStack = 0.20
        static let waveSlowDuration = 1.5
        static let waveSlowTag = KitTags.buff("H029", "waveSlow")
        static let waveMark = "wave"
        /// 3 回ぶんの合計ダメージ ÷ 汎用 S1 のダメージ。0.8〜1.3 の上限寄り（サポートの基礎ダメージは全ロールで最低で、汎用の味方回復の奥義も
        /// キットで置き換えるため。1v1 の勝率で決めた: docs/kits/Tigreal.md の対応表）。
        static let waveRatio = 1.28

        // スキル2 聖槌突撃
        static let dashRange = 420.0
        static let dashSpeed = 1700.0
        /// 経路の当たり半径（対象の半径は別に足す）。
        static let dashWidth = 100.0
        /// 押し運んだ敵を突進の終点の先に置く隙間（半径どうしの和に足す）。
        static let carryGap = 20.0
        /// 到着した tick に当たった敵を押し出す最小の時間。
        static let carryMinTime = 0.12
        static let recastWindow = 4.0
        static let smashDelay = 0.2
        static let smashReach = 320.0
        static let smashHalfAngle = 0.8
        /// 打ち上げの秒数。調査では 0.6 秒と 1 秒で資料が割れている（中間を採用）。
        static let smashAirborne = 0.8
        /// 突進 + 再使用の合計ダメージ ÷ 汎用 S2 のダメージ（上限寄りの理由は waveRatio と同じ）。突進の取り分は dashShare。
        static let hammerRatio = 1.28
        static let dashShare = 0.30

        // アルティメット 崩落聖域（Implosion）
        static let ultReach = 520.0
        /// 詠唱の最初の部分（ultGather 秒。CC で中断できる）と全体。ultGather の終わりに引き寄せ、ultTotal の終わりに爆発。
        static let ultGather = 0.3
        static let ultTotal = 0.8
        /// 引き寄せの所要時間（爆発の前に集まり終わる）と、引き寄せた敵を置く隙間。
        static let ultPullTime = 0.38
        static let ultPullGap = 20.0
        static let ultStun = 1.8
        /// 汎用の奥義（Support は味方回復でダメージ 0）には比べる相手が居ないので、他ロールの奥義と同じ式の結果に掛ける倍率。
        /// クールダウンが汎用の奥義より長い（22〜27 秒 vs 約 17 秒）ぶんと、回復を失うぶんを補う。
        /// 詠唱を調査寄りに長くした（溜め 0.2 → 0.3 秒、全体 0.7 → 0.8 秒。敵の CC で溜めが潰れやすくなる）ぶんと、
        /// スキル1 の波が前へ広がる（遠い敵に当たる波が減る）ぶんの勝率の落ち込みを埋めるため 1.8 → 3.0 にした
        /// （KitBalanceTests のロール中央値との差で決めた値: docs/kits/Tigreal.md）。
        static let ultRatio = 3.0
        static let channelTag = KitTags.buff("H029", "channel")
        /// ボットのアルティメット: 近くに味方ヒーロー（この距離以内）が居るか、相手の HP がこの割合未満のときだけ。敵タワーの射程内では撃たない。
        static let botAllyRange = 900.0
        static let botWeakHP = 0.5

        // クールダウン（MLBB 秒 → ランク間を線形補間 → Balance.Skills.cooldownScale を掛ける）
        static let waveCooldown = (7.0, 4.0)
        static let hammerCooldown = (16.0, 13.0)
        static let ultCooldown = (55.0, 45.0)
    }

    /// HitPayload.kitEvent
    private enum Event {
        static let wave = 1
        static let dash = 2
    }

    /// KitTimer.code
    private enum Code {
        static let wave = 1
        static let smash = 2
        static let ultPull = 3
        static let ultDetonate = 4
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 前方の扇（汎用の近接 S1 と同じ cone）。範囲の半径 = 射程
            var t = base
            t.archetype = .cone
            t.aim = .direction
            t.range = Tune.waveReach
            t.radius = Tune.waveReach
            t.shape = .fan
            t.halfAngle = Tune.waveHalfAngle
            return t
        case .skill2:
            if stage >= 1 {
                // 再使用: 前方の扇を叩く（対象が居なくても撃てる）
                return SkillTargeting(archetype: .cone, aim: .direction, range: Tune.smashReach, radius: Tune.smashReach,
                                      shape: .fan, halfAngle: Tune.smashHalfAngle, recastable: true)
            }
            // 突進（経路上の敵に当たる）。radius は経路の当たり半径
            return SkillTargeting(archetype: .dashStrike, aim: .direction, range: Tune.dashRange,
                                  radius: Tune.dashWidth, shape: .dashToPoint, recastable: true)
        case .ultimate:
            // 自己中心の詠唱（敵が居なくても撃てる）。radius = 引き寄せ・爆発の半径
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.ultReach, shape: .selfRing)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        n.damageType = .physical
        switch slot {
        case .passive:
            n.damage = 0
            n.hits = 1
            n.extras = [KitStat(key: "vows", value: Double(Tune.vowStacks)),
                        KitStat(key: "expire", value: Tune.vowExpire)]
        case .skill1:
            n.hits = Tune.waveCount
            n.damage = base.damage * Tune.waveRatio / Double(Tune.waveCount)
            n.cooldown = Self.cooldown(Tune.waveCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccDuration = Tune.waveSlowDuration
            n.extras = [KitStat(key: "slow1", value: Tune.waveSlowPerStack * 100),
                        KitStat(key: "slow2", value: Tune.waveSlowPerStack * 200),
                        KitStat(key: "slow3", value: Tune.waveSlowPerStack * 300),
                        KitStat(key: "slowDuration", value: Tune.waveSlowDuration),
                        KitStat(key: "reachMult", value: Tune.waveReach / hero.attackRange)]
        case .skill2:
            let total = base.damage * Tune.hammerRatio
            let dash = total * Tune.dashShare
            let smash = total - dash
            n.hits = 1
            n.damage = stage >= 1 ? smash : dash
            n.cc = stage >= 1 ? .knockback : .none
            n.ccDuration = stage >= 1 ? Tune.smashAirborne : 0
            n.cooldown = Self.cooldown(Tune.hammerCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.stages = 2
            n.recastWindow = Tune.recastWindow
            n.extras = [KitStat(key: "dashDamage", value: dash.rounded()),
                        KitStat(key: "smashDamage", value: smash.rounded()),
                        KitStat(key: "airborne", value: Tune.smashAirborne),
                        KitStat(key: "window", value: Tune.recastWindow)]
        case .ultimate:
            n.hits = 1
            n.damage = Self.ultDamage(skill: skill, rank: rank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Tune.ultStun
            // 汎用の味方全体回復は持たない
            n.heal = 0
            n.shield = 0
            n.shieldDuration = 0
            n.damageReduction = 0
            n.damageReductionDuration = 0
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "stun", value: Tune.ultStun),
                        KitStat(key: "channel", value: Tune.ultTotal),
                        KitStat(key: "gather", value: Tune.ultGather),
                        KitStat(key: "reachMult", value: Tune.ultReach / hero.attackRange)]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "スキル1・スキル2・アルティメットを使うか、通常攻撃を受けるたびに「誓い」が1たまる（タワーやジャングルの敵の攻撃も数えるが、ミニオンの攻撃は数えない）。{x0}たまると、次に受ける通常攻撃のダメージを無効化して誓いが消える。最後に誓いが増えてから{x1}秒で消える。",
                en: "Gain a Vow each time you cast Skill 1, Skill 2 or the Ultimate, or are hit by a basic attack (towers and jungle monsters count, minions do not). At {x0} Vows, the next basic attack against you is fully blocked and the Vows are consumed. Vows fade {x1}s after the last one was gained.")
        case .skill1:
            return KitText(
                ja: "前方の扇へ聖槌の衝撃波を、前へ広げながら{hits}回起こし、1回ごとに{damage}ダメージを与える（扇の奥は近接攻撃の射程の約{reachMult}倍。手前の敵ほど多くの波に当たる）。命中するたびに鈍足が深まる（{x0}% → {x1}% → {x2}%、{x3}秒）。クールダウン{cd}秒。",
                en: "Send {hits} hammer shockwaves through the cone ahead, each reaching farther than the last, dealing {damage} damage each (the cone reaches about {reachMult}x your melee attack range; closer enemies are caught by more waves). Every hit deepens the slow ({x0}% → {x1}% → {x2}%, {x3}s). Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "指定方向へ突進し、通り道の敵に{x0}ダメージを与えて突進の終点まで押し運ぶ。{x3}秒以内にスキル2をもう一度使うと、前方の敵に{x1}ダメージを与えて{x2}秒間打ち上げる。再使用の窓が閉じてからクールダウン{cd}秒。",
                en: "Charge in a direction, dealing {x0} damage to enemies along the way and carrying them to the end of the charge. Use again within {x3}s to smash the cone ahead for {x1} damage and knock enemies airborne for {x2}s. The {cd}s cooldown starts when the window closes.")
        case .ultimate:
            return KitText(
                ja: "{x1}秒の詠唱で、近接攻撃の射程の約{reachMult}倍の範囲の敵を引き寄せ、{damage}ダメージを与えて{x0}秒間スタンさせる。詠唱の最初の{x2}秒はスタンなどのCCで、それ以降は制圧（サプレス）でのみ中断される。クールダウン{cd}秒。",
                en: "Channel for {x1}s, pulling in enemies within about {reachMult}x your melee attack range, then dealing {damage} damage and stunning them for {x0}s. The first {x2}s of the channel can be interrupted by crowd control; after that only by suppression. Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 無効化した直後の 0.3 秒だけタイマー（誓いが 4 → 0 になった合図。App の演出がタイマーの開始を見て盾の弾けを出す）
            if k.borgBlockFlash > 0 { return KitBadge(kind: .timer, remaining: k.borgBlockFlash, total: Tune.blockFlash) }
            return KitBadge(kind: .stacks, value: min(k.borgVow, Tune.vowStacks), maxValue: Tune.vowStacks)
        case .ultimate:
            guard k.borgUltPhase != 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.borgChannel, total: Tune.ultTotal)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        switch slot {
        case .ultimate:
            // 自己中心の詠唱: 敵が居なくても撃てる
            let facing = Vec2.fromAngle(s.units[caster].facing)
            return .some(SkillAim(direction: facing, point: s.units[caster].pos, unit: nil, distance: 0))
        case .skill2 where stage >= 1:
            // 詠唱中（奥義）は再使用できない
            if (s.units[caster].hero?.kit?.borgUltPhase ?? 0) != 0 { return .some(nil) }
            return nil
        default:
            return nil
        }
    }

    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        // 奥義の詠唱中は、ほかのスキルを始められない
        (s.units[caster].hero?.kit?.borgUltPhase ?? 0) == 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castWave(&s, c)
        case .skill2: castCharge(&s, ctx, c)
        case .ultimate: castImplosion(&s, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 発動の方向と原点に 3 回、扇の衝撃波を起こす（途中でスタンされても止まらない: すでに地面に走った衝撃波）。
    private func castWave(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        s.units[i].hero!.kit!.borgAim = dir
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.waveReach, unit: c.aim.unit, shape: .fan,
                     halfAngle: Tune.waveHalfAngle,
                     duration: Tune.waveFirstDelay + Tune.waveInterval * Double(Tune.waveCount - 1),
                     count: Tune.waveCount)
        Kit.strikeSequence(&s, caster: i, slot: .skill1, code: Code.wave, count: Tune.waveCount,
                           interval: Tune.waveInterval, firstDelay: Tune.waveFirstDelay, param: c.numbers.damage,
                           point: origin, interruptible: false)
    }

    /// S2 の 1 回目: 突進。通り道の敵にダメージを与え、突進の終点まで押し運ぶ。再使用の窓を開く。
    private func castCharge(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let from = s.units[i].pos
        let dir = c.aim.direction
        var p = HitPayload(damage: c.numbers.damage, damageType: .physical, source: .skill(.skill2),
                           skillID: c.check.skill.skillID, kitEvent: Event.dash)
        p.originPos = from
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * Tune.dashRange,
                                       speed: Tune.dashSpeed, payload: p, radius: Tune.dashWidth)
        let actual = (landing - from).normalized
        s.units[i].hero!.kit!.borgAim = actual == .zero ? dir : actual
        s.units[i].hero!.kit!.borgDashEnd = landing
        Kit.emitCast(&s, c, origin: from, target: landing, unit: c.aim.unit, shape: .dashToPoint,
                     duration: from.distance(to: landing) / Tune.dashSpeed, count: 1)
        // 窓が閉じてからクールダウンを数える（最初の発動のコスト・CD は消費済み）
        Kit.openRecast(&s, caster: i, slot: .skill2, duration: Tune.recastWindow, stage: 1, charges: 1,
                       cooldownOnClose: c.numbers.cooldown)
    }

    /// S2 の再使用: 短い振りかぶりのあと、前方の扇を叩いて打ち上げる。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        guard c.slot == .skill2 else {
            Kit.closeRecast(&s, ctx, caster: c.caster, slot: c.slot)
            return
        }
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        s.units[i].hero!.kit!.borgSmashDir = dir
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.smashReach, unit: c.aim.unit, shape: .fan,
                     halfAngle: Tune.smashHalfAngle, duration: Tune.smashDelay, count: 1)
        Kit.schedule(&s, caster: i, slot: .skill2, code: Code.smash, after: Tune.smashDelay, param: c.numbers.damage,
                     point: origin, interruptible: true)
        Kit.advanceRecast(&s, ctx, caster: i, slot: .skill2)
    }

    /// 奥義: 詠唱の開始。溜め（ultGather 秒）の終わりに引き寄せ、詠唱の終わり（ultTotal 秒）に爆発（どちらも onTimer）。
    private func castImplosion(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let pos = s.units[i].pos
        Kit.emitCast(&s, c, origin: pos, target: pos, shape: .selfRing, duration: Tune.ultTotal, count: 2)
        beginChannel(&s, i)
        // 溜め（CC で中断できる）の終わり = 引き寄せ。それ以降は suppress だけで中断される（CC では取り消されない）
        Kit.schedule(&s, caster: i, slot: .ultimate, code: Code.ultPull, after: Tune.ultGather, interruptible: true)
        Kit.schedule(&s, caster: i, slot: .ultimate, code: Code.ultDetonate, after: Tune.ultTotal,
                     param: c.numbers.damage, interruptible: false)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        switch timer.code {
        case Code.wave: erupt(&s, ctx, owner: owner, timer: timer)
        case Code.smash: smash(&s, ctx, owner: owner, timer: timer)
        case Code.ultPull: pullIn(&s, ctx, owner: owner)
        case Code.ultDetonate: detonate(&s, ctx, owner: owner, timer: timer)
        default: break
        }
    }

    /// スキル1 の 1 回ぶん: 原点から方向の扇にダメージ + 鈍足の層（命中ごとに 1 層、最大 3 層）。
    /// 扇の半径は波ごとに広がる（timer.index 0 → 2 で射程の 0.45 → 0.75 → 1.0 倍）: 手前の敵ほど多くの波に当たり、鈍足が深まる。
    private func erupt(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let dir = s.units[owner].hero?.kit?.borgAim, dir != .zero else { return }
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill1),
                           skillID: Self.skillID(ctx, .skill1),
                           effects: [.addMark(name: Tune.waveMark, stacks: 1, maxStacks: Tune.waveCount,
                                              duration: Tune.waveSlowDuration)],
                           kitEvent: Event.wave)
        let scale = Tune.waveRadiusScale[min(max(0, timer.index), Tune.waveRadiusScale.count - 1)]
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: timer.point, radius: Tune.waveReach * scale,
                                shape: .cone(direction: dir, halfAngle: Tune.waveHalfAngle), payload: p)
    }

    /// S2 の再使用: 今の位置から前方の扇へダメージ + 打ち上げ。
    private func smash(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let dir = s.units[owner].hero?.kit?.borgSmashDir, dir != .zero else { return }
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill2),
                           skillID: Self.skillID(ctx, .skill2), effects: [.knockUp(duration: Tune.smashAirborne)])
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: s.units[owner].pos, radius: Tune.smashReach,
                                shape: .cone(direction: dir, halfAngle: Tune.smashHalfAngle), payload: p)
    }

    /// 奥義の溜めの終わり: 周囲の敵（構造物を除く）を引き寄せる。CC 無効・無敵の相手は動かない。
    private func pullIn(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard s.units[owner].hero?.kit?.borgUltPhase == 1 else { return }
        s.units[owner].hero!.kit!.borgUltPhase = 2
        let team = s.units[owner].team
        let center = s.units[owner].pos
        var pulled = 0
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            let reach = Tune.ultReach + s.units[j].radius
            guard s.units[j].pos.distanceSquared(to: center) <= reach * reach else { continue }
            let gap = s.units[owner].radius + s.units[j].radius + Tune.ultPullGap
            if Kit.pull(&s, ctx, target: j, toward: center, distance: Tune.ultReach, duration: Tune.ultPullTime,
                        gap: gap) { pulled += 1 }
        }
        s.units[owner].hero!.kit!.borgPulled = pulled
    }

    /// 奥義の爆発: 周囲の敵にダメージ + スタン。suppress を受けていれば不発。
    private func detonate(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard s.units[owner].hero?.kit?.borgUltPhase == 2 else { return }
        endChannel(&s, owner)
        guard !s.units[owner].has(.suppress) else { return }
        let stun = StatusEffect(kind: .stun, duration: Tune.ultStun, sourceID: s.units[owner].id,
                                tag: CombatSystem.tagStun)
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.ultimate), statuses: [stun],
                           skillID: Self.skillID(ctx, .ultimate))
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: s.units[owner].pos, radius: Tune.ultReach,
                                shape: .circle, payload: p)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        // 誓いは増えないまま一定時間で消える
        if k.borgVow > 0, k.borgVowTimer <= 0 { s.units[owner].hero!.kit!.borgVow = 0 }

        guard k.borgUltPhase != 0 else { return }
        // 引き寄せたあとは suppress だけが詠唱を止める（溜めの間は KitRuntime がハード CC で取り消す）
        if k.borgUltPhase == 2, s.units[owner].has(.suppress) {
            Kit.cancelScheduled(&s, caster: owner, slot: .ultimate)
            endChannel(&s, owner)
            return
        }
        // 詠唱中は動かず、攻撃も始めない
        s.units[owner].attackTargetID = nil
        s.units[owner].windupRemaining = nil
        s.units[owner].moveIntent = .none
        // 予約が消えていたら（想定外の取り消し）詠唱を終える
        if Kit.scheduledCount(s, caster: owner, code: Code.ultPull) + Kit.scheduledCount(s, caster: owner, code: Code.ultDetonate) == 0 {
            endChannel(&s, owner)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 溜めの間に CC を受けた: 引き寄せの予約が消えたので、爆発の予約も捨てて詠唱を終える（クールダウンは戻らない）
        guard s.units[owner].hero?.kit?.borgUltPhase == 1 else { return }
        Kit.cancelScheduled(&s, caster: owner, slot: .ultimate)
        endChannel(&s, owner)
    }

    // MARK: - C. パッシブ（聖鎚の誓い）

    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {
        guard slot != .passive else { return }
        gainVow(&s, caster)
    }

    func modifyIncomingDamage(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                              source: DamageSource, amount: Double) -> Double {
        // 通常攻撃（ヒーロー・タワー・ジャングルの敵）だけが対象。ミニオンの攻撃・スキル・継続ダメージは数えない
        switch source {
        case .basicAttack, .tower, .monster: break
        default: return amount
        }
        guard let k = s.units[victim].hero?.kit else { return amount }
        if k.borgVow >= Tune.vowStacks {
            s.units[victim].hero!.kit!.borgVow = 0
            s.units[victim].hero!.kit!.borgVowTimer = 0
            s.units[victim].hero!.kit!.borgBlocks = k.borgBlocks + 1
            // 無効化の合図: 自分に 0.3 秒の「blocked」の印 + パッシブのバッジを 0.3 秒だけタイマーにする（誓いの 4 → 0 を App が見分けられる）
            s.units[victim].hero!.kit!.borgBlockFlash = Tune.blockFlash
            let id = s.units[victim].id
            Kit.addMark(&s, target: victim, ownerID: id, tag: KitTags.mark("H029", Tune.blockMark, owner: id),
                        maxStacks: 1, duration: Tune.blockFlash)
            return 0
        }
        gainVow(&s, victim)
        return amount
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let me = s.units[bot].pos
        switch slot {
        case .skill2:
            // 再使用: 敵が前方の扇に入っているか、窓が閉じそうなら叩く
            guard let w = Kit.window(s, caster: bot, slot: .skill2) else { return .useDefault }
            let delta = s.units[target].pos - me
            let dir = delta.normalized
            let reach = Tune.smashReach * 0.85 + s.units[target].radius
            guard dir != .zero, delta.length <= reach || w.remaining < 0.8 else { return .skip }
            return .cast(.direction(dir))
        case .ultimate:
            // 敵ヒーローを 2 体以上巻き込めるか、狙う相手が傷ついているときだけ。さらに、近くに味方ヒーローが居るか
            // 相手の HP が半分未満のときだけ（引き寄せた相手を一人で受けない）。敵タワーの射程内では撃たない
            guard fighting else { return .skip }
            let team = s.units[bot].team
            var heroes = 0
            for j in s.units.indices where s.units[j].kind == .hero && s.units[j].team != team {
                guard CombatSystem.isLiving(s, j), s.isTargetableEnemy(j, of: team) else { continue }
                let reach = Tune.ultReach + s.units[j].radius
                if s.units[j].pos.distanceSquared(to: me) <= reach * reach { heroes += 1 }
            }
            guard heroes >= 2 || (heroes == 1 && s.units[target].hpRatio < 0.8) else { return .skip }
            var supported = s.units[target].hpRatio < Tune.botWeakHP
            if !supported {
                for j in s.units.indices where j != bot && s.units[j].kind == .hero && s.units[j].team == team {
                    guard CombatSystem.isLiving(s, j) else { continue }
                    if s.units[j].pos.distanceSquared(to: me) <= Tune.botAllyRange * Tune.botAllyRange {
                        supported = true
                        break
                    }
                }
            }
            guard supported, !Self.insideEnemyTowerRange(s, bot: bot) else { return .skip }
            return .cast(.none)
        default:
            return .useDefault
        }
    }

    // MARK: - 部品

    /// 敵の構造物（タワー・コア）の攻撃が届く距離か（TowerSystem.inReach と同じ基準: 射程 + 双方の半径）。
    static func insideEnemyTowerRange(_ s: SimState, bot: Int) -> Bool {
        let me = s.units[bot]
        for j in s.units.indices where s.units[j].isStructure && s.units[j].team != me.team {
            guard CombatSystem.isLiving(s, j), s.units[j].stats.attackRange > 0 else { continue }
            let reach = s.units[j].stats.attackRange + s.units[j].radius + me.radius
            if s.units[j].pos.distanceSquared(to: me.pos) <= reach * reach { return true }
        }
        return false
    }

    private func gainVow(_ s: inout SimState, _ i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        s.units[i].hero!.kit!.borgVow = min(Tune.vowStacks, k.borgVow + 1)
        s.units[i].hero!.kit!.borgVowTimer = Tune.vowExpire
    }

    /// 詠唱の開始: 溜めに入り、その場から動けない。攻撃も始めない。
    private func beginChannel(_ s: inout SimState, _ i: Int) {
        let id = s.units[i].id
        s.units[i].hero!.kit!.borgUltPhase = 1
        s.units[i].hero!.kit!.borgChannel = Tune.ultTotal
        s.units[i].attackTargetID = nil
        s.units[i].windupRemaining = nil
        s.units[i].moveIntent = .none
        s.units[i].path.removeAll()
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .root, duration: Tune.ultTotal, sourceID: id,
                                                                 tag: Tune.channelTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .channeling, duration: Tune.ultTotal,
                                                                 sourceID: id, tag: Tune.channelTag))
    }

    private func endChannel(_ s: inout SimState, _ i: Int) {
        s.units[i].hero?.kit?.borgUltPhase = 0
        s.units[i].hero?.kit?.borgChannel = 0
        s.units[i].statuses.removeAll { ($0.kind == .root || $0.kind == .channeling) && $0.tag == Tune.channelTag }
    }

    /// 突進に巻き込んだ敵を、突進の終点の先まで同じ向きに押し運ぶ（到着に間に合う速さで）。CC 無効の相手は動かない。
    private func carry(_ s: inout SimState, _ ctx: SimContext, owner: Int, target t: Int) {
        guard Kit.canDisplace(s, ctx, t), let k = s.units[owner].hero?.kit else { return }
        var dir = k.borgAim
        if dir == .zero { dir = Vec2.fromAngle(s.units[owner].facing) }
        let remaining: Double
        if let d = s.units[owner].displacement, d.kind == .dash {
            remaining = max(Balance.dt, d.duration - d.elapsed)
        } else {
            remaining = Tune.carryMinTime
        }
        let ahead = max(0, (k.borgDashEnd - s.units[t].pos).dot(dir))
        let gap = s.units[owner].radius + s.units[t].radius + Tune.carryGap
        MovementSystem.knockback(&s, ctx, unitIndex: t, direction: dir, distance: ahead + gap, duration: remaining)
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        switch event {
        case Event.dash:
            carry(&s, ctx, owner: owner, target: target)
        case Event.wave:
            // 鈍足は命中ごとに深まる: 20% × 層（1.5 秒、層は命中のたびに持続が戻る）
            let tag = KitTags.mark("H029", Tune.waveMark, owner: s.units[owner].id)
            let stacks = Kit.markStacks(s, target: target, tag: tag)
            guard stacks > 0, CombatSystem.isLiving(s, target) else { return }
            let slow = StatusEffect(kind: .slow, duration: Tune.waveSlowDuration,
                                    magnitude: Tune.waveSlowPerStack * Double(stacks), sourceID: s.units[owner].id,
                                    tag: Tune.waveSlowTag)
            CombatSystem.addStatus(&s, targetIndex: target, slow)
        default:
            break
        }
    }

    /// 奥義のダメージ。汎用の Support の奥義は回復でダメージ 0 なので、他ロールの奥義と同じ式（ランク・攻撃力・魔力・スロット倍率）。
    static func ultDamage(skill: SkillDef, rank: Int, stats: Stats) -> Double {
        let r = min(max(1, rank), SkillSlot.ultimate.maxRank)
        let rankedBase = skill.baseDamage * (1 + Balance.skillDamagePerRank * Double(r - 1))
        let raw = (rankedBase + skill.scalingAttack * stats.attack * Balance.skillAttackScalingFactor
            + skill.scalingPower * stats.abilityPower) * Balance.Skills.damageScale(.ultimate)
        return raw * Tune.ultRatio
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
        ctx.master.skill(hero: "H029", slot: slot)?.skillID
    }
}
