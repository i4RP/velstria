import Foundation

// 担当: kit-H028（docs/SKILL_KITS.md / docs/NEW_HEROES.md）
// H028 断空のザイル = Velstria 版の Saber（MLBB。調査: docs/kits/Saber.md、対応表: 同ファイル末尾）。
// アサシン（近接 150・Energy）。キットはロールの汎用パッシブ（奇襲ボーナス・キル/アシストの全 CD 短縮）を置き換える。
//   パッシブ 空断の理（Enemy's Bane）— ダメージを与えるたび（通常攻撃・スキル）に相手の物理防御を下げる。5 層・5 秒、
//                                      1 層あたり 3（Lv1）→ 8（Lv15）。
//   S1   環剣（Orbiting Swords）     — 5 本の剣が 5 秒間 周囲を回り、触れた敵に接触ダメージ（0.5 秒ごと）。
//                                      周回中に通常攻撃/スキルでダメージを与えるたび、剣が対象へ飛んで「剣撃」
//                                      （貫通した他の敵には 50%）+ スキル2 のクールダウンを縮める。剣撃が主なダメージ源
//                                      （接触は控えめ）。
//   S2   断空突進（Charge）          — 指定方向へ突進して通り道の敵にダメージ。次の通常攻撃が強化（追加ダメージ + 鈍足 60%・1 秒）。
//   奥義 三連断空（Triple Sweep）     — 対象指定（敵ヒーロー）。突進して 1.2 秒打ち上げ、その間に 3 連撃（弱・弱・強）。
//                                      最初の 2 撃には S1 の剣撃が乗る（3 撃目は乗らない）。ハード CC で中断される。
// 再使用の窓は Saber に無いので使わない。
//
// 状態（KitState）:
//   ints[0]  = 奥義の段（0 = なし / 1 = 突進中 / 2 = 三連撃中）  ints[1] = 剣撃を出さない間 1（3 撃目の最中のみ）
//   ints[2]  = 剣撃を出した回数（累計。検証用）                  ints[3] = 奥義の三連撃が当たった回数（累計。検証用）
//   ints[4]  = 直近に防御ダウンを積んだ敵の層の数（パッシブのバッジ用）  ids[1] = その敵
//   timers[0] = 剣が周回している残り秒   timers[1] = 剣撃の最短間隔（同時に何本も飛ばさない）
//   timers[2] = S2 の強化通常攻撃の残り秒   timers[3] = 防御ダウンの層が残っている秒（バッジ。命中のたびに 5 秒へ戻る）
//   reals[0] = 接触ダメージ（1 回）  reals[1] = 剣撃ダメージ  reals[2] = 強化通常攻撃の追加ダメージ  reals[3] = 奥義の平均 1 撃
//   ids[0]   = 奥義の対象

extension KitState {
    var zailUltPhase: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var zailSwordLock: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var zailSwordStrikes: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var zailUltStrikes: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var zailSwordsRemaining: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var zailSwordGap: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var zailChargeWindow: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    var zailPulseDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }

    var zailStrikeDamage: Double {
        get { reals[1] }
        set { reals[1] = newValue }
    }

    var zailChargeBonus: Double {
        get { reals[2] }
        set { reals[2] = newValue }
    }

    var zailUltDamage: Double {
        get { reals[3] }
        set { reals[3] = newValue }
    }

    var zailUltTargetID: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }

    var zailBaneStacks: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    var zailBaneWindow: Double {
        get { timers[3] }
        set { timers[3] = newValue }
    }

    var zailBaneTargetID: EntityID {
        get { ids[1] }
        set { ids[1] = newValue }
    }
}

struct Kit_H028: HeroKit {
    let heroID = "H028"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H028(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100 を近接スキルの射程に合わせて調整）

    enum Tune {
        // パッシブ 空断の理
        static let baneMaxStacks = 5
        static let baneDuration = 5.0
        /// 1 層あたりの防御ダウン（固定値）。Lv1 = 3、最大レベル（15）= 8 を線形に（mlbb.io の値。「7 固定」という古い記述は採らない）。
        static let baneMinPerStack = 3.0
        static let baneMaxPerStack = 8.0
        /// 防御ダウン（割合）の上限。
        static let baneMaxRatio = 0.9
        static let baneMark = "bane"
        static let baneTag = KitTags.buff("H028", "bane")

        // S1 周回する剣
        /// 剣の周回半径（術者の中心から対象の縁まで）。近接の通常攻撃（射程 150 + 半径）の外側まで届く。
        static let orbitRadius = 230.0
        static let swordCount = 5
        static let swordsDuration = 5.0
        /// 接触ダメージの間隔と回数（0.5 秒ごとに 9 回 = 4.5 秒。5 秒で剣が戻る）。
        static let pulseInterval = 0.5
        static let pulseCount = 9
        /// 接触ダメージの合計 ÷ 汎用 S1 のダメージ。剣撃が主なダメージ源（調査: 接触 80〜105 + 30% に対し剣撃は 210〜260 + 60%）
        /// なので、接触は控えめにした。
        static let contactRatio = 0.55
        /// 剣撃 1 本のダメージ ÷ 汎用 S1 のダメージ（主対象。貫通した他の敵は passRatio 倍）。
        static let strikeRatio = 0.19
        /// S1 の単体総ダメージの予算（汎用の 0.8〜1.3 倍）に数える剣撃の本数の目安: 5 秒の間に通常攻撃・スキルが 3 回当たる想定。
        static let budgetStrikes = 3
        static let strikeDelay = 0.12
        /// 剣撃どうしの最短間隔（多段ヒットのスキルで一度に何本も飛ばさない）。
        static let strikeGap = 0.35
        /// 剣撃が届く最大距離（術者の中心から対象の縁まで）。
        static let strikeReach = 450.0
        static let strikePassRadius = 80.0
        static let strikePassOvershoot = 100.0
        static let strikePassRatio = 0.5
        /// 剣撃 1 本あたりの S2 のクールダウン短縮（MLBB は 1 秒。Velstria はクールダウンが半分なので同じ割合の 0.5 秒）。
        static let chargeRefund = 1.0 * Balance.Skills.cooldownScale

        // S2 突進
        static let dashRange = 350.0
        static let dashSpeed = 1800.0
        /// 経路の当たり半径（対象の半径は別に足す）。
        static let dashWidth = 70.0
        /// 突進のダメージ ÷ 汎用 S2 のダメージ。
        static let dashRatio = 0.81
        /// 強化通常攻撃の追加ダメージ ÷ 汎用 S2 のダメージ（MLBB は通常攻撃を 75 + 総攻撃力 120% に置き換える。突進より
        /// 強化した通常攻撃のほうが大きいので、突進 0.81 + 追加 0.25 = 1.06 倍で S2 の予算に収める）。
        static let chargeBonusRatio = 0.23
        /// 強化通常攻撃を撃てる時間（調査に「不明」とある値なので、汎用の強化通常攻撃（blinkEmpower）に合わせた）。
        static let enhanceWindow = Balance.Skills.empowerDuration
        static let slowAmount = 0.6
        static let slowDuration = 1.0
        static let slowTag = KitTags.buff("H028", "chargeSlow")

        // 奥義 三連断空
        /// 突進の届く距離（術者の中心から対象の縁まで）。調査の 4.6（旧 5.9）に対し、マスターは 600。
        static let ultReach = 500.0
        static let ultSpeed = 2600.0
        static let ultGap = 10.0
        /// 到着時に対象がこれより離れていたら外れ（突進の追尾はしない）。
        static let ultSlack = 260.0
        static let airborne = 1.2
        static let strikeCount = 3
        static let ultFirstDelay = 0.2
        static let ultInterval = 0.4
        /// 1〜3 撃目の重み（120 : 120 : 240 = 0.75 : 0.75 : 1.5。合計 3 = 平均 1 撃 × 3）。
        static let ultWeights: [Double] = [0.75, 0.75, 1.5]
        /// 三連撃の合計 ÷ 汎用奥義のダメージ。打ち上げ 1.2 秒の確定コンボ・防御ダウン 3 層・剣撃 2 本が乗るので、予算の下限寄り
        /// （クールダウンは汎用より長い 22 → 18 秒。1v1 の勝率で決めた: docs/kits/Saber.md の対応表）。
        static let ultRatio = 0.85
        static let channelTag = KitTags.buff("H028", "channel")
        /// ボットが関門を待たずに奥義を撃つ、敵ヒーローの HP の割合の上限（打ち上げ中の 3 連撃 + 防御ダウンで削り切れる目安）。
        static let botExecuteRatio = 0.6

        // クールダウン（MLBB 秒 → ランク間を線形補間 → Balance.Skills.cooldownScale を掛ける）
        /// S1 は全ランク 10 秒（調査: 2 つの資料が 10 秒で一定、Fandom の抜粋は 9 秒。10 秒を採る）。
        static let swordsCooldown = (10.0, 10.0)
        /// S1 の倍率 = 全体倍率（0.5）。クールダウン 5 秒 = 持続 5 秒なので、剣はほぼ常に回る（MLBB は 10 秒で約 50%）。
        /// 秒数そのまま（1.0）に近づけると Lv1（スキル1 だけ）の勝率が崩れるので採らなかった: 1v1 の総当たりで
        /// 倍率 0.5 = Lv1 34% / 0.6 = 22% / 0.65 = 13% / 0.75 以上 = 3%（Lv1 の決闘は 10 秒前後で、2 回目の剣が間に合うかで決まる）。
        /// 倍率 1.0 にダメージを上乗せして補っても（接触 0.75・剣撃 0.28）Lv1 は 3% のままだった。
        static let swordsCooldownScale = Balance.Skills.cooldownScale
        static let chargeCooldown = (7.0, 7.0)
        static let ultCooldown = (44.0, 36.0)
    }

    /// KitTimer.code
    private enum Code {
        static let pulse = 1
        static let swordStrike = 2
        static let chargeArrive = 3
        static let ultArrive = 4
        static let ultStrike = 5
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 自己中心（剣が周囲を回る）。radius = 周回半径
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.orbitRadius, shape: .selfRing)
        case .skill2:
            // 指定方向への突進（経路上の敵に当たる）。radius は経路の当たり半径
            return SkillTargeting(archetype: .dashStrike, aim: .direction, range: Tune.dashRange,
                                  radius: Tune.dashWidth, shape: .dashToPoint)
        case .ultimate:
            // 敵ヒーローを指定して突進（居なければ消費せず失敗）
            return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.ultReach, radius: 120,
                                  shape: .lockOn, requiresTarget: true)
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
            n.extras = [KitStat(key: "baneMin", value: Tune.baneMinPerStack),
                        KitStat(key: "baneMax", value: Tune.baneMaxPerStack),
                        KitStat(key: "stacks", value: Double(Tune.baneMaxStacks)),
                        KitStat(key: "duration", value: Tune.baneDuration)]
        case .skill1:
            n.hits = Tune.pulseCount
            n.damage = base.damage * Tune.contactRatio / Double(Tune.pulseCount)
            n.cc = .none
            n.ccDuration = 0
            n.cooldown = Self.cooldown(Tune.swordsCooldown, rank: rank, maxRank: slot.maxRank, stats: stats,
                                       scale: Tune.swordsCooldownScale)
            n.extras = [KitStat(key: "strikeDamage", value: (base.damage * Tune.strikeRatio).rounded()),
                        KitStat(key: "duration", value: Tune.swordsDuration),
                        KitStat(key: "refund", value: Tune.chargeRefund),
                        KitStat(key: "passPercent", value: Tune.strikePassRatio * 100)]
        case .skill2:
            n.hits = 1
            n.damage = base.damage * Tune.dashRatio
            // 鈍足は強化通常攻撃につく
            n.cc = .slow
            n.ccDuration = Tune.slowDuration
            n.cooldown = Self.cooldown(Tune.chargeCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "bonusDamage", value: (base.damage * Tune.chargeBonusRatio).rounded()),
                        KitStat(key: "slowPercent", value: Tune.slowAmount * 100),
                        KitStat(key: "slowDuration", value: Tune.slowDuration),
                        KitStat(key: "window", value: Tune.enhanceWindow)]
        case .ultimate:
            n.hits = Tune.strikeCount
            n.damage = base.damage * Tune.ultRatio / Double(Tune.strikeCount)
            n.missingHealthRatio = 0
            n.cc = .knockback
            n.ccIsUltimate = true
            n.ccDuration = Tune.airborne
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "strike1", value: (n.damage * Tune.ultWeights[0]).rounded()),
                        KitStat(key: "strike3", value: (n.damage * Tune.ultWeights[2]).rounded()),
                        KitStat(key: "airborne", value: Tune.airborne),
                        KitStat(key: "interval", value: Tune.ultInterval)]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        let gap = String(format: "%g", Tune.strikeGap)
        switch slot {
        case .passive:
            return KitText(
                ja: "通常攻撃やスキルでダメージを与えるたびに、相手の物理防御を下げる層が1つ積まれる（最大{x2}層、{x3}秒。ダメージを与えるたびに持続が戻る）。"
                    + "1層あたり防御−{x0}で、レベルが上がるほど大きくなり、最大レベルでは−{x1}。ヒーローと中立モンスターが対象で、ミニオンには積まれない。",
                en: "Every time you deal damage with a basic attack or a skill, you add a stack that lowers the target's physical defense (up to {x2} stacks for {x3}s, refreshed on every hit). "
                    + "Each stack removes {x0} defense, growing with level to {x1} at max level. It affects heroes and neutral monsters, not minions.")
        case .skill1:
            return KitText(
                ja: "{x1}秒間、5本の剣が周囲{radius}を回り、触れた敵に0.5秒ごとに{damage}ダメージ（最大{hits}回）を与える。"
                    + "周回中に通常攻撃かスキルでダメージを与えると「剣撃」が起き、剣が対象へ飛んで{x0}ダメージを与え（貫通した他の敵には{x3}%）、断空突進のクールダウンが{x2}秒縮む（剣撃は\(gap)秒に1回まで）。"
                    + "クールダウン{cd}秒。",
                en: "For {x1}s, 5 swords orbit within {radius} of you, hitting enemies they touch for {damage} every 0.5s (up to {hits} times). "
                    + "While they orbit, each time you damage a target with a basic attack or skill, a sword strike follows: a sword flies at it for {x0} damage ({x3}% to other enemies it passes through) and shortens Charge's cooldown by {x2}s (at most once every \(gap)s). "
                    + "Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "指定方向へ最大{range}突進し、通り道の敵に{damage}ダメージを与える。突進後{x3}秒以内の次の通常攻撃が強化され、{x0}ダメージが加わって{x1}%の鈍足を{x2}秒与える。クールダウン{cd}秒（環剣の剣撃で短縮）。",
                en: "Dash up to {range} in a direction, dealing {damage} damage to enemies along the way. Within {x3}s of the dash, your next basic attack is enhanced: it deals {x0} extra damage and slows by {x1}% for {x2}s. Cooldown {cd}s (reduced by sword strikes).")
        case .ultimate:
            return KitText(
                ja: "{range}以内の敵ヒーローへ突進して{x2}秒間打ち上げ、その間に3連撃する（{x0}・{x0}・{x1}ダメージ、合計{total}）。連撃の間は動けず、スタンなどで中断される。最初の2撃には環剣の剣撃が乗る。クールダウン{cd}秒。",
                en: "Dash at an enemy hero within {range}, knock them airborne for {x2}s and strike three times ({x0}, {x0}, {x1} damage, {total} total). You cannot act during the strikes and stuns interrupt them. The first two strikes also trigger sword strikes. Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 直近に防御ダウンを積んだ敵の層の数（残りの時間があるあいだ）。層が増えるたびに演出のパッシブの合図が出る
            guard k.zailBaneWindow > 0, k.zailBaneStacks > 0 else { return nil }
            return KitBadge(kind: .stacks, value: min(Tune.baneMaxStacks, k.zailBaneStacks), maxValue: Tune.baneMaxStacks)
        case .skill1:
            guard k.zailSwordsRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.zailSwordsRemaining, total: Tune.swordsDuration)
        case .skill2:
            guard k.zailChargeWindow > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.zailChargeWindow, total: Tune.enhanceWindow)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        // 奥義の突進・三連撃の間は、ほかのスキルを始められない
        (s.units[caster].hero?.kit?.zailUltPhase ?? 0) == 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castSwords(&s, c)
        case .skill2: castCharge(&s, ctx, c)
        case .ultimate: castTripleSweep(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 剣が周囲を回る。0.5 秒ごとに接触ダメージ（CC では止まらない）。
    private func castSwords(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        // 重ね掛け（クールダウンのリセットなど）は予約を作り直す
        Kit.cancelScheduled(&s, caster: i, slot: .skill1, code: Code.pulse)
        let n = c.numbers
        s.units[i].hero!.kit!.zailSwordsRemaining = Tune.swordsDuration
        s.units[i].hero!.kit!.zailPulseDamage = n.damage
        // 剣撃のダメージ = 汎用 S1 のダメージ × strikeRatio（接触の合計 = 汎用 S1 × contactRatio から逆算）
        s.units[i].hero!.kit!.zailStrikeDamage = n.damage * Double(n.hits) / Tune.contactRatio * Tune.strikeRatio
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing,
                     duration: Tune.swordsDuration, count: Tune.swordCount)
        Kit.strikeSequence(&s, caster: i, slot: .skill1, code: Code.pulse, count: Tune.pulseCount,
                           interval: Tune.pulseInterval, firstDelay: Tune.pulseInterval, param: n.damage,
                           interruptible: false)
    }

    /// S2: 指定方向への突進。通り道の敵に 1 度ずつダメージ。到着で次の通常攻撃が強化される。
    private func castCharge(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let from = s.units[i].pos
        let dir = c.aim.direction
        var distance = c.aim.distance
        if let u = c.aim.unit {
            // 対象を指定したときは対象の縁で止まる
            distance = max(0, min(Tune.dashRange, distance - s.units[u].radius - s.units[i].radius - 5))
        }
        distance = min(distance, Tune.dashRange)
        s.units[i].hero!.kit!.zailChargeBonus = c.numbers.damage / Tune.dashRatio * Tune.chargeBonusRatio
        var p = HitPayload(damage: c.numbers.damage, damageType: .physical, source: .skill(.skill2),
                           skillID: c.check.skill.skillID)
        p.originPos = from
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * distance,
                                       speed: Tune.dashSpeed, payload: p, radius: Tune.dashWidth,
                                       arriveCode: Code.chargeArrive)
        Kit.emitCast(&s, c, origin: from, target: landing, unit: c.aim.unit, shape: .dashToPoint,
                     duration: from.distance(to: landing) / Tune.dashSpeed, count: 1)
    }

    /// 奥義: 対象の敵ヒーローへ突進。到着で打ち上げて三連撃を予約する（onTimer）。
    private func castTripleSweep(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let from = s.units[i].pos
        let toTarget = s.units[t].pos - from
        let dir = toTarget.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : toTarget.normalized
        // 対象の縁（術者の半径込み）で止まる
        let gap = s.units[i].radius + s.units[t].radius + Tune.ultGap
        let travel = min(Tune.ultReach, max(0, toTarget.length - gap))
        s.units[i].hero!.kit!.zailUltTargetID = s.units[t].id
        s.units[i].hero!.kit!.zailUltDamage = c.numbers.damage
        s.units[i].hero!.kit!.zailUltPhase = 1
        // 経路上の敵には当たらない（affectsEnemies = false）。ハード CC の中断と着地の通知だけを使う
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.ultimate), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .ultimate, to: from + dir * travel,
                                       speed: Tune.ultSpeed, payload: carrier, radius: 0, arriveCode: Code.ultArrive)
        let dash = from.distance(to: landing) / Tune.ultSpeed
        Kit.emitCast(&s, c, origin: from, target: s.units[t].pos, unit: t, shape: .lockOn,
                     duration: dash + Tune.ultFirstDelay + Tune.ultInterval * Double(Tune.strikeCount - 1),
                     count: Tune.strikeCount)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        switch timer.code {
        case Code.pulse: pulse(&s, ctx, owner: owner, timer: timer)
        case Code.swordStrike: sendSword(&s, ctx, owner: owner, timer: timer)
        case Code.chargeArrive:
            s.units[owner].hero?.kit?.zailChargeWindow = Tune.enhanceWindow
        case Code.ultArrive: ultArrive(&s, ctx, owner: owner)
        case Code.ultStrike: ultStrike(&s, ctx, owner: owner, timer: timer)
        default: break
        }
    }

    /// S1 の接触ダメージ 1 回: 周回半径内の敵（構造物を除く）。
    private func pulse(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill1),
                           skillID: Self.skillID(ctx, .skill1))
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: s.units[owner].pos, radius: Tune.orbitRadius,
                                shape: .circle, payload: p)
    }

    /// 剣撃: 主対象にダメージ + S2 のクールダウン短縮、軌道上の他の敵に 50%。
    private func sendSword(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), !s.units[t].isStructure,
              s.units[t].team != s.units[owner].team else { return }
        let me = s.units[owner].pos
        let tp = s.units[t].pos
        let reach = Tune.strikeReach + s.units[t].radius
        guard me.distanceSquared(to: tp) <= reach * reach else { return }
        let dir = (tp - me).normalized == .zero ? Vec2.fromAngle(s.units[owner].facing) : (tp - me).normalized
        let end = tp + dir * Tune.strikePassOvershoot
        // 軌道上の敵は先に確定（命中中の死亡で判定が変わらないように）
        var others: [Int] = []
        for j in s.units.indices where j != t && s.units[j].team != s.units[owner].team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            if distancePointToSegment(s.units[j].pos, me, end) <= Tune.strikePassRadius + s.units[j].radius {
                others.append(j)
            }
        }
        let skillID = Self.skillID(ctx, .skill1)
        let ownerID = s.units[owner].id
        let team = s.units[owner].team
        let main = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill1), skillID: skillID,
                              effects: [.refundCooldown(slot: .skill2, seconds: Tune.chargeRefund)])
        CombatSystem.applyHit(&s, ctx, sourceID: ownerID, team: team, targetIndex: t, payload: main, from: me)
        guard CombatSystem.isLiving(s, owner) else { return }
        let pass = HitPayload(damage: timer.param * Tune.strikePassRatio, damageType: .physical,
                              source: .skill(.skill1), skillID: skillID)
        for j in others {
            CombatSystem.applyHit(&s, ctx, sourceID: ownerID, team: team, targetIndex: j, payload: pass, from: me)
        }
    }

    /// 奥義の到着: 打ち上げて三連撃を予約する。対象が居ない・離れすぎ・対象不可なら外れ。
    private func ultArrive(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit, k.zailUltPhase == 1 else { return }
        guard let t = s.index(of: k.zailUltTargetID), CombatSystem.isLiving(s, t),
              s.units[t].team != s.units[owner].team, !s.units[t].has(.untargetable) else {
            endUlt(&s, owner)
            return
        }
        let reach = s.units[owner].radius + s.units[t].radius + Tune.ultSlack
        guard s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else {
            endUlt(&s, owner)
            return
        }
        let id = s.units[owner].id
        s.units[owner].hero!.kit!.zailUltPhase = 2
        // 打ち上げ（CC 無効・無敵の相手には掛からないが、三連撃は続ける）
        Kit.knockUp(&s, target: t, duration: Tune.airborne, sourceID: id)
        let face = (s.units[t].pos - s.units[owner].pos)
        if face != .zero { s.units[owner].facing = face.angle }
        // 三連撃の間は動かない（スタンなどで中断される）
        let span = Tune.ultFirstDelay + Tune.ultInterval * Double(Tune.strikeCount - 1) + 0.1
        s.units[owner].attackTargetID = nil
        s.units[owner].windupRemaining = nil
        s.units[owner].moveIntent = .none
        s.units[owner].path.removeAll()
        CombatSystem.addStatus(&s, targetIndex: owner, StatusEffect(kind: .root, duration: span, sourceID: id,
                                                                      tag: Tune.channelTag))
        CombatSystem.addStatus(&s, targetIndex: owner, StatusEffect(kind: .channeling, duration: span, sourceID: id,
                                                                      tag: Tune.channelTag))
        Kit.strikeSequence(&s, caster: owner, slot: .ultimate, code: Code.ultStrike, count: Tune.strikeCount,
                           interval: Tune.ultInterval, firstDelay: Tune.ultFirstDelay, targetID: k.zailUltTargetID,
                           param: k.zailUltDamage, interruptible: true)
    }

    /// 奥義の 1 撃。対象が倒れた・離れすぎたら残りを取り消して終える。3 撃目は剣撃を乗せない。
    private func ultStrike(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard s.units[owner].hero?.kit?.zailUltPhase == 2 else { return }
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), s.units[t].team != s.units[owner].team
        else {
            Kit.cancelScheduled(&s, caster: owner, slot: .ultimate, code: Code.ultStrike)
            endUlt(&s, owner)
            return
        }
        let reach = s.units[owner].radius + s.units[t].radius + Tune.ultSlack
        guard s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else {
            Kit.cancelScheduled(&s, caster: owner, slot: .ultimate, code: Code.ultStrike)
            endUlt(&s, owner)
            return
        }
        let last = timer.index >= Tune.strikeCount - 1
        let weight = Tune.ultWeights[min(max(0, timer.index), Tune.ultWeights.count - 1)]
        var p = HitPayload(damage: timer.param * weight, damageType: .physical, source: .skill(.ultimate),
                           skillID: Self.skillID(ctx, .ultimate))
        p.originPos = s.units[owner].pos
        if last { s.units[owner].hero!.kit!.zailSwordLock = 1 }
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
        s.units[owner].hero?.kit?.zailSwordLock = 0
        s.units[owner].hero?.kit?.zailUltStrikes += 1
        if last { endUlt(&s, owner) }
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // バッジの敵が倒れた・居なくなったら層の表示を消す
        if let b = s.units[owner].hero?.kit, b.zailBaneWindow > 0 {
            let alive = s.index(of: b.zailBaneTargetID).map { CombatSystem.isLiving(s, $0) } ?? false
            if !alive {
                s.units[owner].hero!.kit!.zailBaneWindow = 0
                s.units[owner].hero!.kit!.zailBaneStacks = 0
                s.units[owner].hero!.kit!.zailBaneTargetID = 0
            }
        }
        guard let k = s.units[owner].hero?.kit, k.zailUltPhase != 0 else { return }
        // 奥義の突進・三連撃の間は、通常攻撃を始めない・動かない
        s.units[owner].attackTargetID = nil
        s.units[owner].windupRemaining = nil
        s.units[owner].moveIntent = .none
        // 想定外に予約・突進が消えていたら終える（状態を残さない）
        if k.zailUltPhase == 1, k.sweep == nil {
            endUlt(&s, owner)
        } else if k.zailUltPhase == 2, Kit.scheduledCount(s, caster: owner, code: Code.ultStrike) == 0 {
            endUlt(&s, owner)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 突進中・三連撃中のハード CC: 予約は取り消し済み。奥義の状態を畳む（クールダウンは戻らない）
        guard (s.units[owner].hero?.kit?.zailUltPhase ?? 0) != 0 else { return }
        Kit.cancelScheduled(&s, caster: owner, slot: .ultimate, code: Code.ultStrike)
        endUlt(&s, owner)
    }

    // MARK: - C. パッシブ

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        guard damage > 0, s.units[attacker].hero?.kit != nil else { return }
        afterDamage(&s, ctx, owner: attacker, target: target, trigger: true)
    }

    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double) {
        // 「ダメージを与えた」ときだけ（CC のみの命中は数えない）。S1（接触・剣撃）は防御ダウンは入れるが剣撃は呼ばない
        guard damage > 0, s.units[attacker].hero?.kit != nil else { return }
        afterDamage(&s, ctx, owner: attacker, target: target, trigger: slot != .skill1)
    }

    private func afterDamage(_ s: inout SimState, _ ctx: SimContext, owner: Int, target t: Int, trigger: Bool) {
        applyBane(&s, ctx, owner: owner, target: t)
        guard trigger, let k = s.units[owner].hero?.kit, k.zailSwordsRemaining > 0, k.zailSwordGap <= 0,
              k.zailSwordLock == 0, s.units.indices.contains(t), !s.units[t].isStructure,
              s.units[t].team != s.units[owner].team else { return }
        s.units[owner].hero!.kit!.zailSwordGap = Tune.strikeGap
        s.units[owner].hero!.kit!.zailSwordStrikes = k.zailSwordStrikes + 1
        Kit.schedule(&s, caster: owner, slot: .skill1, code: Code.swordStrike, after: Tune.strikeDelay,
                     targetID: s.units[t].id, param: k.zailStrikeDamage, interruptible: false)
    }

    /// 空断の理: 防御ダウンの層を積む（最大 5 層・5 秒、命中のたびに持続が戻る）。ヒーロー・モンスター・人形が対象
    /// （ミニオンは対象外。構造物には効かない）。
    private func applyBane(_ s: inout SimState, _ ctx: SimContext, owner: Int, target t: Int) {
        guard s.units.indices.contains(t), CombatSystem.isLiving(s, t), s.units[t].team != s.units[owner].team else {
            return
        }
        switch s.units[t].kind {
        case .hero, .monster, .dummy: break
        default: return
        }
        let ownerID = s.units[owner].id
        let tag = KitTags.mark("H028", Tune.baneMark, owner: ownerID)
        let stacks = Kit.addMark(&s, target: t, ownerID: ownerID, tag: tag, maxStacks: Tune.baneMaxStacks,
                                 duration: Tune.baneDuration)
        guard stacks > 0 else { return }
        // バッジ用: 直近に積んだ敵の層の数と、残り時間（命中のたびに 5 秒へ戻る）
        s.units[owner].hero!.kit!.zailBaneStacks = stacks
        s.units[owner].hero!.kit!.zailBaneWindow = Tune.baneDuration
        s.units[owner].hero!.kit!.zailBaneTargetID = s.units[t].id
        // 防御ダウンは割合（armorShred）。今の防御（ほかの防御ダウンを含む）から、ダウン前の防御を求めて換算する
        var shredNow = 0.0
        for st in s.units[t].statuses where st.kind == .armorShred { shredNow = max(shredNow, st.magnitude) }
        if shredNow > 0 { StatCalculator.recompute(&s, t, ctx) }
        let armor = s.units[t].stats.armor / max(0.05, 1 - min(0.95, shredNow))
        guard armor > 1 else { return }
        let level = s.units[owner].hero?.level ?? 1
        let ratio = min(Tune.baneMaxRatio, Double(stacks) * Self.baneFlat(level: level) / armor)
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .armorShred, duration: Tune.baneDuration,
                                                                 magnitude: ratio, sourceID: ownerID,
                                                                 tag: Tune.baneTag))
        // 同じ tick の続きのダメージ（剣撃・奥義の次の一撃）から効くように能力値を更新する
        StatCalculator.recompute(&s, t, ctx)
    }

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard let k = s.units[attacker].hero?.kit, k.zailChargeWindow > 0 else { return }
        // 強化通常攻撃: 追加ダメージ + 鈍足（1 回で消える）
        plan.payload.damage += k.zailChargeBonus
        plan.payload.statuses.append(StatusEffect(kind: .slow, duration: Tune.slowDuration, magnitude: Tune.slowAmount,
                                                  sourceID: s.units[attacker].id, tag: Tune.slowTag))
        s.units[attacker].hero!.kit!.zailChargeWindow = 0
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let me = s.units[bot].pos
        let foe = s.units[target]
        switch slot {
        case .skill2:
            // 突進: 交戦中、対象へ向けて（対象の縁で止まる）
            guard fighting, foe.id != 0 else { return .skip }
            let reach = targeting.reach + foe.radius + 100
            guard me.distanceSquared(to: foe.pos) <= reach * reach else { return .skip }
            return .cast(.unit(foe.id))
        case .ultimate:
            // 交戦中の敵ヒーローが射程内のとき。倒しやすい（HP が少ない）なら関門を待たずに今撃つ。
            // それ以外は汎用の関門（倒せる・2 体以上）を通ったときだけ（剣が回っているかどうかでは決めない）
            guard fighting, foe.kind == .hero else { return .skip }
            let reach = Tune.ultReach + foe.radius
            guard me.distanceSquared(to: foe.pos) <= reach * reach else { return .skip }
            if foe.hpRatio <= Tune.botExecuteRatio { return .castNow(.unit(foe.id)) }
            return .cast(.unit(foe.id))
        default:
            return .useDefault
        }
    }

    // MARK: - 部品

    private func endUlt(_ s: inout SimState, _ i: Int) {
        s.units[i].hero?.kit?.zailUltPhase = 0
        s.units[i].hero?.kit?.zailUltTargetID = 0
        s.units[i].statuses.removeAll { ($0.kind == .root || $0.kind == .channeling) && $0.tag == Tune.channelTag }
    }

    /// 1 層あたりの防御ダウン（固定値）。レベル 1〜最大レベルで線形。
    static func baneFlat(level: Int) -> Double {
        let t = Double(min(max(1, level), Balance.maxLevel) - 1) / Double(max(1, Balance.maxLevel - 1))
        return Tune.baneMinPerStack + (Tune.baneMaxPerStack - Tune.baneMinPerStack) * t
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、Velstria の全体倍率と CD 短縮を掛ける。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats,
                         scale: Double = Balance.Skills.cooldownScale) -> Double {
        let sec = lerp(range.0, range.1, rank: rank, maxRank: maxRank)
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * scale
    }

    private static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H028", slot: slot)?.skillID
    }
}
