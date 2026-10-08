import Foundation

// 担当: kit-H034（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Franco.md）
// H034 鎖鉤のゴルム = Velstria 版の Franco（MLBB。調査: docs/kits/Franco.md、対応表: 同ファイル末尾）。
//   パッシブ 鉄鎖の執念    — 5 秒ダメージを受けないと 移動速度 +10%・毎秒 最大 HP の 1% 回復、闘気が 1 秒に 1 つたまる（最大 10）。
//                           次に使うスキルが闘気をすべて消費し、1 つにつきそのスキルのダメージ +15%（最大 +150%）。ダメージで解除。
//                           ロール「サポート」の味方回復パッシブ・奥義の味方回復はキットが置き換える。
//   S1   鎖鉤              — 射程 680 の非貫通の鉤。最初に当たった敵（ミニオン・モンスター含む、タワーは除く）に物理ダメージ、
//                           自分の足元まで引き寄せてスタン。壁は越えて飛び、引き寄せは壁の手前で止まる。
//   S2   怒りの鎖          — 自身中心の範囲に 固定部分 + 自分の最大 HP の 4% の物理ダメージ、70% 減速 1.5 秒。
//   奥義 狩猟鎖獄          — 敵ヒーロー 1 体を指定。踏み込んで 1.8 秒 suppress（解除不可・CC 無効も無視）し、その間に 6 回殴る。
//                           ゴルムも動けず、スタン等で中断されると相手は解放される。
// 再使用の窓は Franco に無いので使わない。
//
// 状態（KitState）:
//   ints[0]   = 闘気（0..10）            ints[1] = 「5 秒の無被弾」状態に入っているか（0/1）
//   ints[2]   = 奥義の段（0 = なし / 1 = 踏み込み中 / 2 = 拘束中）   ints[3] = 拘束中に殴った回数
//   ints[4]   = 命中した鉤の数（検証用）  ints[5] = 直前のスキルが消費した闘気の数（検証用）
//   timers[0] = 最後のダメージからの待ち（5 秒）  timers[1] = 次の闘気まで   timers[2] = 次の回復まで
//   timers[3] = 奥義の拘束の残り秒
//   ids[0]    = 奥義の対象                reals[0] = 奥義の 1 撃のダメージ（闘気の補正込み）

extension KitState {
    var gormStacks: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var gormCalmActive: Bool {
        get { ints[1] != 0 }
        set { ints[1] = newValue ? 1 : 0 }
    }

    var gormUltPhase: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var gormUltStrikes: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var gormHooksLanded: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    var gormLastConsumed: Int {
        get { ints[5] }
        set { ints[5] = newValue }
    }

    var gormCalm: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var gormStackTimer: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var gormRegenTimer: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    var gormUltRemaining: Double {
        get { timers[3] }
        set { timers[3] = newValue }
    }

    var gormUltTarget: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }

    var gormUltDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }
}

struct Kit_H034: HeroKit {
    let heroID = "H034"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H034(isReady: true)` を HeroKits.testOverride に差しても試せる（有効化とは独立）。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100。調査に無い値は Franco.md の対応表に理由）

    enum Tune {
        // パッシブ 鉄鎖の執念
        /// 最後のダメージからこの秒数 ダメージを受けないと「無被弾」状態に入る。
        static let calmDelay = 5.0
        static let calmSpeed = 0.10
        /// 毎秒の回復（最大 HP の割合）。回復は regenPulse 秒ごとにまとめて行う（イベントを増やさない）。
        static let calmRegen = 0.01
        static let regenPulse = 0.5
        static let maxStacks = 10
        /// 闘気は無被弾の間 1 秒に 1 つ（調査に無い: 10 個で 15 秒＝無被弾の 5 秒 + 10 秒）。
        static let stackInterval = 1.0
        /// 1 つにつきスキルのダメージ +15%（調査: 最大 +150% の 1/10）。
        static let stackBonus = 0.15
        static let speedTag = KitTags.buff("H034", "calmSpeed")
        /// 「ダメージを受けるまで続く」加速のステータスに持たせる持続（実質無期限）。
        static let permanent = 1_000_000.0

        // S1 鎖鉤
        static let hookRange = 680.0
        /// 鉤の当たり幅（半径）。ヒーロー半径 55 と合わせて、左右 110 の筋に届く。
        static let hookWidth = 55.0
        static let hookSpeed = 1800.0
        /// 引き寄せの所要時間（この間は強制移動で動けない）。
        static let hookPull = 0.30
        /// 引き寄せた後に止まる、端同士の隙間。
        static let hookGap = 10.0
        /// 命中から数えるスタンの長さ（引き寄せ 0.30 秒 + 着いてから 0.7 秒）。調査は「引き寄せの間」だけなので、
        /// 味方が続けて攻撃するための猶予を足した調整（汎用のスタン 0.75 秒より少し長い。鉤は 6〜7 秒に 1 度）。
        static let hookStun = 1.0
        static let hookStunTag = KitTags.buff("H034", "hookStun")
        /// 汎用 S1（扇形）のダメージに対する倍率（単体 + 引き寄せ + スタンのぶん、汎用より少し上）。
        static let hookDamageRatio = 1.30

        // S2 怒りの鎖
        static let shockRadius = 260.0
        static let shockSlow = 0.70
        static let shockSlowDuration = 1.5
        static let shockSlowTag = KitTags.buff("H034", "shockSlow")
        /// 自分の最大 HP の 4%。
        static let shockMaxHPRatio = 0.04
        /// 汎用 S2 のダメージに対する固定部分の倍率（これに自分の最大 HP の 4% が乗って、汎用の 1.1〜1.3 倍になる）。
        static let shockFlatRatio = 0.98

        // 奥義 狩猟鎖獄
        /// 術者の中心から対象の縁までの射程（短い）。
        static let ultReach = 350.0
        static let ultSuppress = 1.8
        static let ultHits = 6
        /// 拘束してから最初の 1 撃まで・撃つ間隔（6 回が拘束の 1.8 秒に収まる: 0.15, 0.45, ... 1.65）。
        static let ultFirst = 0.15
        static let ultInterval = 0.30
        /// 汎用の式で出した奥義（ランク 1）のダメージ（サポートの汎用の奥義は回復でダメージ 0 なので自前で計算）に対する、6 回の合計の倍率。
        /// クールダウンが汎用（34 秒 × 0.5）より長い（62 → 48 秒 × 0.5）ぶんの補正で、1 秒あたりでは汎用の 1.1〜1.25 倍。
        static let ultTotalRatio = 2.1
        /// ランクごとの倍率（MLBB は 1 撃 50 / 60 / 70 = 1 : 1.2 : 1.4。汎用の +30%/ランクより緩やか）。
        static let ultRankScale: [Double] = [1.0, 1.2, 1.4]
        static let ultRushSpeed = 2600.0
        /// 踏み込んだ後に止まる、端同士の隙間。
        static let ultContactGap = 10.0
        /// 踏み込み終わりにこれより離れていたら外れ（追尾はしない）。
        static let ultSlack = 140.0
        static let lockRootTag = KitTags.buff("H034", "lockRoot")
        static let lockTag = KitTags.buff("H034", "lock")

        // クールダウン（MLBB 秒 → ランク間を線形補間 → Balance.Skills.cooldownScale を掛ける）
        static let hookCooldown = (15.0, 11.0)
        /// MLBB の 7.0 → 4.5 秒そのまま（汎用の S2 は 9.8 秒 × 0.5）。
        static let shockCooldown = (7.0, 4.5)
        static let ultCooldown = (62.0, 48.0)
    }

    private enum Code {
        static let strike = 1
        static let ultArrive = 2
    }

    /// HitPayload.kitEvent
    private enum Event {
        static let hook = 1
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 長い直線の鉤（非貫通）。radius は弾の半幅
            return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: Tune.hookRange,
                                  radius: Tune.hookWidth, shape: .wideLine)
        case .skill2:
            // 自身中心の範囲（対象なし）
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.shockRadius,
                                  shape: .selfRing)
        case .ultimate:
            // 対象指定（敵ヒーロー 1 体）。必要なら踏み込む
            return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.ultReach, radius: 150,
                                  shape: .lockOn, requiresTarget: true)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.hits = Tune.maxStacks
            n.extras = [KitStat(key: "calmDelay", value: Tune.calmDelay),
                        KitStat(key: "speedPercent", value: Tune.calmSpeed * 100),
                        KitStat(key: "regenPercent", value: Tune.calmRegen * 100),
                        KitStat(key: "stackPercent", value: Tune.stackBonus * 100)]
        case .skill1:
            n.damage = base.damage * Tune.hookDamageRatio
            n.cooldown = Self.cooldown(Tune.hookCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccDuration = Tune.hookStun
            n.extras = [KitStat(key: "stun", value: Tune.hookStun),
                        KitStat(key: "pull", value: Tune.hookPull)]
        case .skill2:
            n.damage = base.damage * Tune.shockFlatRatio + stats.maxHP * Tune.shockMaxHPRatio
            n.cooldown = Self.cooldown(Tune.shockCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccDuration = Tune.shockSlowDuration
            n.extras = [KitStat(key: "slowPercent", value: Tune.shockSlow * 100),
                        KitStat(key: "slowDuration", value: Tune.shockSlowDuration),
                        KitStat(key: "maxHPPercent", value: Tune.shockMaxHPRatio * 100)]
        case .ultimate:
            // 汎用のサポートの奥義は味方回復（ダメージなし）。単体ダメージの目安は、同じ式で ult のダメージを出した値（ランク 1）。
            // ランクの伸びは MLBB の 50 / 60 / 70 に合わせる
            let r = min(max(1, rank), Tune.ultRankScale.count)
            n.damage = Self.genericUltimateDamage(skill, rank: 1, stats: stats) * Tune.ultRankScale[r - 1]
                * Tune.ultTotalRatio / Double(Tune.ultHits)
            n.hits = Tune.ultHits
            n.heal = 0
            n.shield = 0
            n.shieldDuration = 0
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Tune.ultSuppress
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "suppress", value: Tune.ultSuppress),
                        KitStat(key: "interval", value: Tune.ultInterval)]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "{x0}秒間ダメージを受けないと、移動速度が{x1}%上がり、毎秒最大HPの{x2}%を回復して、闘気が1秒に1個たまり始める（最大{hits}個）。"
                    + "次に使うスキルが闘気をすべて消費し、1つにつきそのスキルのダメージが+{x3}%される。ダメージを受けると回復と加速は止まる。",
                en: "After {x0}s without taking damage, gain {x1}% movement speed, recover {x2}% of max HP per second and "
                    + "start gaining 1 Resolve per second (up to {hits}). Your next skill consumes all Resolve, "
                    + "dealing +{x3}% damage per stack. Taking damage ends the recovery and speed bonus.")
        case .skill1:
            return KitText(
                ja: "指定方向へ射程{range}の鎖鉤を打ち出し、最初に当たった敵に{damage}の物理ダメージ。"
                    + "当たった敵を自分の足元まで引き寄せ、{x0}秒スタンさせる（壁は越えて飛び、引き寄せは壁の手前で止まる。タワーには当たらない）。"
                    + "クールダウン{cd}秒。",
                en: "Fires a chain hook of {range} range that deals {damage} physical damage to the first enemy hit, "
                    + "drags them to your feet and stuns them for {x0}s (flies over walls, but the pull stops at walls; "
                    + "does not hit turrets). Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "周囲{radius}の敵を鎖で打ち据え、{damage}の物理ダメージ（自分の最大HPの{x2}%を含む）を与え、{x1}秒間 移動速度を{x0}%下げる。"
                    + "クールダウン{cd}秒。",
                en: "Lashes enemies within {radius} for {damage} physical damage (including {x2}% of your max HP) and slows "
                    + "them by {x0}% for {x1}s. Cooldown {cd}s.")
        case .ultimate:
            return KitText(
                ja: "射程{range}の敵ヒーロー1体を指定して踏み込み、{x0}秒間 鎖で抑え込む（解除不可・CC無効も無視。相手のスキルは中断される）。"
                    + "その間に{hits}回、1回ごとに{damage}の物理ダメージ。ゴルムも動けず、スタンなどで中断されると相手は解放される。"
                    + "クールダウン{cd}秒。",
                en: "Pick an enemy hero within {range}, rush in and chain them down for {x0}s (cannot be cleansed, ignores "
                    + "crowd-control immunity, and cancels their skills). Strikes {hits} times for {damage} physical damage "
                    + "each. Gorm cannot move meanwhile, and being stunned or interrupted frees the target. Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            return KitBadge(kind: .stacks, value: min(k.gormStacks, Tune.maxStacks), maxValue: Tune.maxStacks)
        case .ultimate:
            guard k.gormUltRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.gormUltRemaining, total: Tune.ultSuppress)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        guard slot == .ultimate else { return nil }
        // 敵ヒーロー 1 体の対象指定: 射程内に居なければ拒否（コスト・CD を消費しない）
        guard let u = Self.pickHero(s, caster: caster, reach: targeting.reach, target: target) else {
            return .some(nil)
        }
        return .some(SkillAiming.aim(at: u, s, caster: caster, range: targeting.range,
                                     facing: Vec2.fromAngle(s.units[caster].facing)))
    }

    /// 奥義の最中は、他のスキルも奥義も撃てない（鎖で相手と繋がっている）。
    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        (s.units[caster].hero?.kit?.gormUltPhase ?? 0) == 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castHook(&s, c)
        case .skill2: castShock(&s, ctx, c)
        case .ultimate: castHunt(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// 闘気をすべて消費し、そのスキルのダメージ倍率（1 + 0.15 × 闘気）を返す。外れても消費する（調査: 次のスキルの発動で消費）。
    private func consumeStacks(_ s: inout SimState, _ i: Int) -> Double {
        guard let k = s.units[i].hero?.kit else { return 1 }
        let n = k.gormStacks
        s.units[i].hero!.kit!.gormStacks = 0
        s.units[i].hero!.kit!.gormLastConsumed = n
        return 1 + Tune.stackBonus * Double(n)
    }

    /// S1: 非貫通の鉤。最初に当たった敵へダメージ + スタン + 足元への引き寄せ。
    private func castHook(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let amp = consumeStacks(&s, i)
        let stun = StatusEffect(kind: .stun, duration: Tune.hookStun, sourceID: s.units[i].id, tag: Tune.hookStunTag)
        // 距離は十分に大きく取る（実際の移動量は gap で決まる）
        let pull = HitEffect.pullToOwner(distance: Tune.hookRange + 400, duration: Tune.hookPull, gap: Tune.hookGap)
        let p = HitPayload(damage: c.numbers.damage * amp, damageType: c.numbers.damageType, source: .skill(.skill1),
                           statuses: [stun], skillID: c.check.skill.skillID, effects: [pull],
                           originPos: s.units[i].pos, kitEvent: Event.hook)
        Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * Tune.hookRange, unit: c.aim.unit,
                     shape: .wideLine, duration: Tune.hookRange / Tune.hookSpeed, count: 1)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: c.aim.direction, maxDistance: Tune.hookRange),
                               speed: Tune.hookSpeed, width: Tune.hookWidth, pierce: false, payload: p,
                               visual: c.check.skill.effectID)
    }

    /// S2: 自身中心の円。固定部分 + 自分の最大 HP の 4%（numbers に含まれる）に闘気の補正、70% 減速。
    private func castShock(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let amp = consumeStacks(&s, i)
        let slow = StatusEffect(kind: .slow, duration: Tune.shockSlowDuration, magnitude: Tune.shockSlow,
                                sourceID: s.units[i].id, tag: Tune.shockSlowTag)
        let p = HitPayload(damage: c.numbers.damage * amp, damageType: c.numbers.damageType, source: .skill(.skill2),
                           statuses: [slow], skillID: c.check.skill.skillID, originPos: s.units[i].pos)
        Kit.emitCast(&s, c, target: s.units[i].pos, shape: .selfRing, count: 1)
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: s.units[i].pos, radius: c.targeting.radius, shape: .circle,
                                payload: p)
    }

    /// 奥義: 対象へ踏み込み（離れていれば）、着いたら拘束して 6 回殴る。
    private func castHunt(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let amp = consumeStacks(&s, i)
        s.units[i].hero!.kit!.gormUltTarget = s.units[t].id
        s.units[i].hero!.kit!.gormUltDamage = c.numbers.damage * amp
        Kit.emitCast(&s, c, target: s.units[t].pos, unit: t, shape: .lockOn, duration: Tune.ultSuppress,
                     count: Tune.ultHits)

        let from = s.units[i].pos
        let to = s.units[t].pos
        let gap = s.units[i].radius + s.units[t].radius + Tune.ultContactGap
        let dist = from.distance(to: to)
        guard dist - gap > 1 else {
            beginLock(&s, ctx, owner: i)
            return
        }
        // 踏み込み（経路上の敵には当てない carrier。ハード CC の中断と着地の通知だけを使う）
        s.units[i].hero!.kit!.gormUltPhase = 1
        let dir = (to - from).normalized
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.ultimate), affectsEnemies: false)
        Kit.dashSweeping(&s, ctx, caster: i, slot: .ultimate, to: from + dir * (dist - gap), speed: Tune.ultRushSpeed,
                         payload: carrier, radius: 0, arriveCode: Code.ultArrive)
    }

    /// 拘束の開始: 対象を suppress し、自分は動けない詠唱に入り、6 回の連撃を予約する。成立しなければ何もせず終わる。
    private func beginLock(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        let tid = k.gormUltTarget
        guard tid != 0, let t = s.index(of: tid), CombatSystem.isLiving(s, t), s.units[t].team != s.units[i].team,
              s.units[t].kind == .hero else {
            endLock(&s, owner: i, release: false)
            return
        }
        let reach = s.units[i].radius + s.units[t].radius + Tune.ultContactGap + Tune.ultSlack
        guard s.units[i].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else {
            endLock(&s, owner: i, release: false)
            return
        }
        let id = s.units[i].id
        Kit.suppress(&s, target: t, duration: Tune.ultSuppress, sourceID: id)
        // 無敵などで拘束できなかった（suppress が付かない）なら、連撃に入らない
        guard s.units[t].has(.suppress) else {
            endLock(&s, owner: i, release: false)
            return
        }
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .root, duration: Tune.ultSuppress, sourceID: id,
                                                                 tag: Tune.lockRootTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .channeling, duration: Tune.ultSuppress,
                                                                 sourceID: id, tag: Tune.lockTag))
        let face = s.units[t].pos - s.units[i].pos
        if face != .zero { s.units[i].facing = face.angle }
        s.units[i].windupRemaining = nil
        s.units[i].hero!.kit!.gormUltPhase = 2
        s.units[i].hero!.kit!.gormUltRemaining = Tune.ultSuppress
        s.units[i].hero!.kit!.gormUltStrikes = 0
        Kit.strikeSequence(&s, caster: i, slot: .ultimate, code: Code.strike, count: Tune.ultHits,
                           interval: Tune.ultInterval, firstDelay: Tune.ultFirst, targetID: tid)
    }

    /// 奥義の終わり（自然終了・対象の消失・中断）。release なら相手の拘束も外す。
    private func endLock(_ s: inout SimState, owner i: Int, release: Bool) {
        guard s.units[i].hero?.kit != nil else { return }
        if release { Kit.releaseSuppress(&s, bySource: s.units[i].id) }
        s.units[i].statuses.removeAll {
            ($0.kind == .root && $0.tag == Tune.lockRootTag) || ($0.kind == .channeling && $0.tag == Tune.lockTag)
        }
        Kit.cancelScheduled(&s, caster: i, slot: .ultimate)
        s.units[i].hero!.kit!.gormUltPhase = 0
        s.units[i].hero!.kit!.gormUltRemaining = 0
        s.units[i].hero!.kit!.gormUltTarget = 0
        s.units[i].hero!.kit!.gormUltDamage = 0
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let k = s.units[owner].hero?.kit else { return }
        switch timer.code {
        case Code.ultArrive:
            guard k.gormUltPhase == 1 else { return }
            beginLock(&s, ctx, owner: owner)
        case Code.strike:
            guard k.gormUltPhase == 2, k.gormUltTarget == timer.targetID else { return }
            strike(&s, ctx, owner: owner, timer: timer)
        default:
            break
        }
    }

    /// 拘束中の 1 撃。対象が倒れた・居なくなった・拘束が外れていたら、残りの連撃を取りやめて解放する。
    private func strike(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), s.units[t].has(.suppress) else {
            endLock(&s, owner: i, release: true)
            return
        }
        let damage = s.units[i].hero?.kit?.gormUltDamage ?? 0
        let p = HitPayload(damage: damage, damageType: .physical, source: .skill(.ultimate), ccIsUltimate: true,
                           skillID: Self.skillID(ctx, .ultimate), originPos: s.units[i].pos)
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: s.units[i].team, targetIndex: t, payload: p,
                              from: s.units[i].pos)
        s.units[i].hero?.kit?.gormUltStrikes += 1
        if !CombatSystem.isLiving(s, t) { endLock(&s, owner: i, release: true) }
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard event == Event.hook, s.units[owner].hero?.kit != nil else { return }
        s.units[owner].hero!.kit!.gormHooksLanded += 1
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        // カウントダウンは 0 まで減らすだけで厳密には 0 にならないことがある（浮動小数の端数）
        let eps = 1e-6

        // 奥義の拘束中: 通常攻撃はしない。時間が来たら終わり（相手の拘束は自然に切れる）
        if k.gormUltPhase == 2 {
            if k.gormUltRemaining <= eps {
                endLock(&s, owner: i, release: false)
            } else {
                s.units[i].windupRemaining = nil
                if s.units[i].attackCooldown < 0.1 { s.units[i].attackCooldown = 0.1 }
            }
        }

        // パッシブ: 5 秒ダメージを受けていない間の加速・回復・闘気
        guard k.gormCalm <= eps else { return }
        let id = s.units[i].id
        if !k.gormCalmActive {
            s.units[i].hero!.kit!.gormCalmActive = true
            s.units[i].hero!.kit!.gormStackTimer = Tune.stackInterval
            s.units[i].hero!.kit!.gormRegenTimer = Tune.regenPulse
        } else if k.gormStackTimer <= eps {
            s.units[i].hero!.kit!.gormStacks = min(Tune.maxStacks, k.gormStacks + 1)
            s.units[i].hero!.kit!.gormStackTimer = Tune.stackInterval
        }
        if !s.units[i].statuses.contains(where: { $0.kind == .speedBoost && $0.tag == Tune.speedTag }) {
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: Tune.permanent,
                                                                     magnitude: Tune.calmSpeed, sourceID: id,
                                                                     tag: Tune.speedTag))
        }
        if s.units[i].hero!.kit!.gormRegenTimer <= eps, s.units[i].hp < s.units[i].stats.maxHP {
            s.units[i].hero!.kit!.gormRegenTimer = Tune.regenPulse
            // 自己再生（回復強化・回復量スコア・アシスト記録の対象外。被回復の増減は受ける）
            CombatSystem.restoreHealth(&s, ctx, sourceID: id, targetIndex: i,
                                       amount: s.units[i].stats.maxHP * Tune.calmRegen * Tune.regenPulse, isVamp: true)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 踏み込み・拘束中のハード CC（スタン・打ち上げ・suppress）: 連撃は取り消され、相手は解放される
        guard (s.units[owner].hero?.kit?.gormUltPhase ?? 0) != 0 else { return }
        endLock(&s, owner: owner, release: true)
    }

    // MARK: - C. パッシブ（鉄鎖の執念）

    func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?, amount: Double) {
        guard amount > 0, s.units[victim].hero?.kit != nil else { return }
        // 無被弾の待ちをやり直し。加速と回復は止まり、闘気はそのまま残る（調査: 減衰の規則は不明）
        s.units[victim].hero!.kit!.gormCalm = Tune.calmDelay
        s.units[victim].hero!.kit!.gormCalmActive = false
        s.units[victim].hero!.kit!.gormStackTimer = 0
        s.units[victim].hero!.kit!.gormRegenTimer = 0
        s.units[victim].statuses.removeAll { $0.kind == .speedBoost && $0.tag == Tune.speedTag }
    }

    // MARK: - 部品

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

    /// 汎用の式でこの奥義のダメージを出した値（軽減前。サポートの汎用の奥義は回復で、ダメージ 0 のため自前で計算する）。
    static func genericUltimateDamage(_ skill: SkillDef, rank: Int, stats: Stats) -> Double {
        let r = min(max(1, rank), skill.slot.maxRank)
        let rankedBase = skill.baseDamage * (1 + Balance.skillDamagePerRank * Double(r - 1))
        return (rankedBase + skill.scalingAttack * stats.attack * Balance.skillAttackScalingFactor
            + skill.scalingPower * stats.abilityPower) * Balance.Skills.damageScale(skill.slot)
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H034", slot: slot)?.skillID
    }

    /// 奥義の対象の選び方: 指定ユニット → 指定地点に近い敵 → 向きに近い敵 → 自動（HP + シールド最小）。
    /// すべて「術者の中心から対象の縁まで reach 以内」の視認中の敵ヒーロー（無敵・対象不可を除く）。
    static func pickHero(_ s: SimState, caster i: Int, reach: Double, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func inReach(_ j: Int) -> Bool {
            guard j != i, s.units[j].kind == .hero, s.isTargetableEnemy(j, of: team),
                  !s.units[j].has(.invulnerable) else { return false }
            let r = reach + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), inReach(j) { return j }

        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where inReach(j) {
            let key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d):
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(d.normalized) / len : 1
                key = (1 - cosine) * 1e7 + len
            case .unit, .none:
                key = max(0, s.units[j].hp) + s.units[j].totalShield
            }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }
}
