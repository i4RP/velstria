import Foundation

// 担当: kit-H031（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Aurora.md）
// H031 氷嵐のオーリア = MLBB オーロラの Velstria 版（アルカニスト・遠隔 550・マナ）。
// 氷の魔導士。パッシブは「致命傷を受けると無効にして 1.5 秒凍りつく（無敵・最大 HP の 30% を少しずつ回復、CD 150 秒）」、
// S1 は地点に落ちる氷塊（鈍足）と続く 5 つの雹、S2 は遅れて広がる扇状の霜風（離れた敵を凍結）と扇の先の凍った地面、
// 奥義は前へ走る氷の道（大幅な鈍足）が氷河に育って砕け、範囲の敵を凍結する（魔力で凍結が延びる）。
// 対応表は docs/kits/Aurora.md の「Velstria 実装対応表」。

/// オーリアの調整値（docs/kits/Aurora.md の数値を Velstria の単位・TTK に合わせたもの）。
enum OriaTuning {
    // MARK: パッシブ（氷の誇り）
    static let prideFreeze: Double = 1.5
    /// 回復量（最大 HP の割合）は英雄のレベルで伸びる: Lv1 の prideHealLv1（0%）→ Lv12（prideHealFullLevel）以降は prideHealRatio（MLBB と同じ 30%）。
    /// 氷の誇りは序盤ほど実質の耐久を大きく伸ばす（致命傷を 1 回無効にして 1.5 秒の無敵 + 回復）ため、総当たりの勝率が
    /// アルカニスト中央値より Lv1 で +59 pt（Lv6 +27 / Lv12 +19）と突出していた。回復を 5% にしても Lv1 は +45 pt 台に残る（無敵の 1.5 秒が効く）ので、
    /// Lv1 は回復なし（無敵の猶予のみ）とした。
    static let prideHealLv1: Double = 0.0
    static let prideHealRatio: Double = 0.30
    /// 回復量が最大になるレベル（総当たりの計測は Lv1 / 6 / 12。ゲームの最大レベルは 15）。
    static let prideHealFullLevel = 12
    static let prideCooldown: Double = 150

    // MARK: S1（氷塊と雹）
    /// 汎用の S1（遠隔直線弾）のダメージに対する倍率。氷塊 + 雹 5 発がすべて 1 体に当たって 0.92 倍。
    /// 氷塊 0.85 + 雹 5 × 0.06 = 1.15 倍（全部当たったとき）。雹を氷塊の周りへ広げた（中心に立つ相手には当たらない）ぶん、氷塊を 0.64 から上げた
    /// （S1 だけの Lv1 と全スキルの Lv12 を同時に合わせるため。0.64 のままだと Lv12 が中央値より下がった）。
    static let s1MeteorRatio: Double = 0.85
    static let s1HailRatio: Double = 0.06
    static let s1Hails = 5
    static let s1Range: Double = 650
    /// 氷塊の半径（スキル定義の radius 155 より少し広く）。
    static let s1Radius: Double = 170
    /// 氷塊が落ちるまで（地点 AoE の標準の予告）。
    static let s1Delay: Double = 0.5
    static let s1Slow: Double = 0.40
    static let s1SlowDuration: Double = 1.0
    /// 雹 1 つの半径と、氷塊の着弾後に降り始めるまで・間隔。氷塊の中心に立つ相手には 5 発とも当たる。
    static let hailRadius: Double = 85
    static let hailGap: Double = 0.2
    static let hailInterval: Double = 0.1
    /// 雹の落ちる位置: 氷塊の中心から氷塊の半径の何割か（奇数番は外側）。0.45 / 0.65 → 0.9 / 1.2 に広げた（中心を外れた位置に降る）。
    static let hailRingInner: Double = 0.9
    static let hailRingOuter: Double = 1.2

    // MARK: S2（霜風）
    /// 汎用の遠隔 S2 は「ブリンク + 強化攻撃」で数値が半分になっているため、基準は元のスキル値（base ÷ empowerRatio）。
    static let s2HitRatio: Double = 0.46
    static let s2PatchRatio: Double = 0.36
    static let s2Range: Double = 650
    /// 扇の半角（約 29°。全体で約 57°）。
    static let s2HalfAngle: Double = 0.65
    /// 霜風が広がるまでの遅れ（この間に避けられる）。
    static let s2Delay: Double = 0.3
    static let s2Freeze: Double = 1.0
    /// 術者からこれ未満の敵は凍らない（ダメージのみ。パッチ 1.8.56 の仕様）。
    static let s2FreezeMin: Double = 200
    /// 凍った地面: 扇の先、中心は術者から range − patchBack の位置。
    static let s2PatchBack: Double = 110
    static let s2PatchDuration: Double = 1.8
    static let s2PatchInterval: Double = 0.5
    /// 凍った地面が当てる回数（発動 + 以降の間隔ごと = 4 回。合計が s2PatchRatio）。
    static let s2PatchTicks = 4

    // MARK: 奥義（氷河）
    static let ultPathRatio: Double = 0.10
    static let ultShatterRatio: Double = 0.90
    static let ultRange: Double = 770
    static let ultPathSpeed: Double = 2200
    /// 氷の道の半幅（当たり幅）。
    static let ultPathWidth: Double = 120
    static let ultPathSlow: Double = 0.80
    static let ultPathSlowDuration: Double = 1.2
    /// 氷河（7.5 × 7 マス ≒ 直径 720）の中心は術者から前へ、半径。氷の道（長さ 770）のほぼ全体を覆う。
    static let ultGlacierCenter: Double = 450
    static let ultGlacierRadius: Double = 360
    /// 氷の道を撃ってから砕けるまで（氷河が育つ時間）。
    static let ultGlacierDelay: Double = 1.2
    static let ultFreeze: Double = 1.0
    /// 魔力 100 ごとに凍結が延びる秒数と、延びの上限（スタン連鎖を防ぐ）。
    static let ultFreezePerHundredAP: Double = 0.2
    static let ultFreezeMaxBonus: Double = 0.6

    // MARK: クールダウン（MLBB の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
    /// オーロラ: S1 6.0 → 4.0 / S2 13 秒（ヒーローページ。パッチの 13 → 11 は不採用）/ 奥義 50 / 45 / 40 秒。
    /// 以前は S1 を汎用の CD（6.5 → 5.3 秒）、奥義を 40 → 32 秒に縮めていた。
    static let s1Cooldown = (6.0, 4.0)
    static let s2Cooldown = (13.0, 13.0)
    static let ultCooldown = (50.0, 40.0)

    // MARK: タグ・コード
    static let s1SlowTag = KitTags.buff("H031", "hailSlow")
    static let freezeTag = KitTags.buff("H031", "freeze")
    static let pathSlowTag = KitTags.buff("H031", "pathSlow")
    static let prideSuppressTag = KitTags.buff("H031", "prideFreeze")
    static let prideInvulnerableTag = KitTags.buff("H031", "prideGuard")

    /// HitPayload.kitEvent
    enum Event {
        static let breeze = 1
    }
}

extension KitState {
    /// 氷の誇りの再発動までの残り秒（死亡しても残る）。
    var oriaPrideCooldown: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    /// 凍りついている残り秒（HUD のバッジ用）。
    var oriaFreezeLeft: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    /// 氷の誇りが働いた回数（検証用）。
    var oriaSaves: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    /// 凍結中の回復の残り tick 数と 1 tick あたりの量。
    var oriaHealTicks: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var oriaHealPerTick: Double {
        get { reals[2] }
        set { reals[2] = newValue }
    }

    /// 霜風を撃った位置（近すぎる敵を凍らせない判定の起点。遅れて広がるので、撃った時点の位置を持つ）。
    var oriaBreezeOrigin: Vec2 {
        get { Vec2(reals[0], reals[1]) }
        set {
            reals[0] = newValue.x
            reals[1] = newValue.y
        }
    }
}

struct Kit_H031: HeroKit {
    let heroID = "H031"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H031(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    typealias T = OriaTuning

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 地点指定の氷塊（HUD は地点の円、ボットは地点 AoE として狙う）
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: T.s1Range, radius: T.s1Radius,
                                  shape: .circleAtPoint)
        case .skill2:
            // 扇状の霜風（radius = 扇の半径）
            return SkillTargeting(archetype: .cone, aim: .direction, range: T.s2Range, radius: T.s2Range,
                                  shape: .fan, halfAngle: T.s2HalfAngle)
        case .ultimate:
            // 照準の帯の半幅 = 氷河の半径（氷河が砕けて凍らせる範囲。氷の道そのものの当たり幅は T.ultPathWidth で別）
            return SkillTargeting(archetype: .piercingLine, aim: .direction, range: T.ultRange, radius: T.ultGlacierRadius,
                                  shape: .wideLine)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.extras = [KitStat(key: "freeze", value: T.prideFreeze),
                        KitStat(key: "heal", value: T.prideHealRatio * 100),
                        KitStat(key: "cooldown", value: T.prideCooldown),
                        KitStat(key: "healMin", value: T.prideHealLv1 * 100)]
        case .skill1:
            n.damage = base.damage * T.s1MeteorRatio
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccIsUltimate = false
            n.ccDuration = T.s1SlowDuration
            n.delay = T.s1Delay
            n.extras = [KitStat(key: "slow", value: T.s1Slow * 100),
                        KitStat(key: "slowDuration", value: T.s1SlowDuration),
                        KitStat(key: "hails", value: Double(T.s1Hails)),
                        KitStat(key: "hailDamage", value: (base.damage * T.s1HailRatio).rounded())]
        case .skill2:
            // 汎用の遠隔 S2 は半分になっているので、元のスキル値を基準にする
            let raw = base.damage / Balance.Skills.empowerRatio
            n.damage = raw * T.s2HitRatio
            n.cooldown = Self.cooldown(T.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = false
            n.ccDuration = T.s2Freeze
            n.delay = T.s2Delay
            n.extras = [KitStat(key: "freeze", value: T.s2Freeze),
                        KitStat(key: "patchDuration", value: T.s2PatchDuration),
                        KitStat(key: "patchTotal", value: (raw * T.s2PatchRatio).rounded()),
                        KitStat(key: "freezeMin", value: T.s2FreezeMin)]
        case .ultimate:
            n.damage = base.damage * T.ultPathRatio
            n.cooldown = Self.cooldown(T.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Self.glacierFreeze(abilityPower: stats.abilityPower)
            n.delay = T.ultGlacierDelay
            n.extras = [KitStat(key: "slow", value: T.ultPathSlow * 100),
                        KitStat(key: "slowDuration", value: T.ultPathSlowDuration),
                        KitStat(key: "shatterDamage", value: (base.damage * T.ultShatterRatio).rounded()),
                        KitStat(key: "freeze", value: Self.glacierFreeze(abilityPower: stats.abilityPower))]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "氷の誇り。致命的なダメージを受けると、そのダメージを無効にして{x0}秒間凍りつく。凍っている間は行動できないが無敵で、最大HPを少しずつ回復する"
                    + "（回復量はレベルで伸び、レベル1で{healMin}%、レベル\(T.prideHealFullLevel)以降で{x1}%）。次に働くまで{x2}秒。復活系の装備より先に働く。",
                en: "Pride of Ice. When you would take fatal damage, negate it and freeze yourself for {x0}s. While frozen you cannot act but are invulnerable "
                    + "and gradually recover max HP (the amount grows with level: {healMin}% at level 1, {x1}% from level \(T.prideHealFullLevel)). "
                    + "Cooldown {x2}s. Triggers before revival items.")
        case .skill1:
            return KitText(
                ja: "指定した地点に氷塊を落とし、{damage}ダメージと{x0}%の減速（{x1}秒）を与える。そのあと氷塊のまわり（中心を外れた位置）に{x2}個の雹が降り注ぎ、1つにつき{x3}ダメージを与える。クールダウン{cd}秒。",
                en: "Drop a block of ice on the target area, dealing {damage} damage and slowing by {x0}% for {x1}s. Then {x2} hailstones fall around it (just off its center), each dealing {x3} damage. Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "前方の扇形に霜風を放ち、少し遅れて{damage}ダメージを与える。術者から{x3}以上離れた敵は{x0}秒凍結する（近すぎると凍らない）。扇の先には凍った地面が残り、{x1}秒間に合計{x2}ダメージを与える。クールダウン{cd}秒。",
                en: "Release a frost breeze in a cone ahead that lands after a short delay, dealing {damage} damage. Enemies at least {x3} away from you are frozen for {x0}s (too close and they are not). A frozen patch is left at the far end, dealing {x2} damage in total over {x1}s. Cooldown {cd}s.")
        case .ultimate:
            return KitText(
                ja: "前方へ氷の道を走らせ、触れた敵に{damage}ダメージと{x0}%の減速（{x1}秒）を与える。しばらくすると氷河が広がって砕け、範囲内の敵すべてに{x2}ダメージを与えて{x3}秒凍結させる（魔力100ごとに凍結が\(T.ultFreezePerHundredAP)秒延びる）。クールダウン{cd}秒。",
                en: "Send a frost path ahead, dealing {damage} damage and slowing enemies it touches by {x0}% for {x1}s. After a moment the path grows into a glacier and shatters, dealing {x2} damage to every enemy in the area and freezing them for {x3}s (each 100 ability power adds \(T.ultFreezePerHundredAP)s). Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard slot == .passive, let k = hero.kit else { return nil }
        if k.oriaFreezeLeft > 0 {
            return KitBadge(kind: .timer, remaining: k.oriaFreezeLeft, total: T.prideFreeze)
        }
        if k.oriaPrideCooldown > 0 {
            return KitBadge(kind: .timer, remaining: k.oriaPrideCooldown, total: T.prideCooldown)
        }
        // 準備できている（全員に見える表示）
        return KitBadge(kind: .stacks, value: 1, maxValue: 1)
    }

    // MARK: - B. 実行

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castHail(&s, ctx, c)
        case .skill2: castBreeze(&s, ctx, c)
        case .ultimate: castGlacier(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 氷塊（0.5 秒後に着弾、鈍足）→ 続けて雹 5 発（氷塊の周りに決まった並びで降る）。
    private func castHail(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        let center = c.aim.point
        let skillID = c.check.skill.skillID
        let hail = Self.hailDamage(c.numbers)
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: center, shape: .circleAtPoint, duration: T.s1Delay,
                     count: T.s1Hails)

        let slow = StatusEffect(kind: .slow, duration: T.s1SlowDuration, magnitude: T.s1Slow, sourceID: id,
                                tag: T.s1SlowTag)
        let meteor = HitPayload(damage: c.numbers.damage, damageType: c.numbers.damageType, source: .skill(.skill1),
                                statuses: [slow], skillID: skillID)
        ZoneSystem.spawn(&s, ownerIndex: i, center: center, radius: T.s1Radius, delay: T.s1Delay, payload: meteor,
                         visual: c.check.skill.effectID)

        // 雹: 向きから決まる角度で 5 方向、内側・外側を交互に（乱数なし）
        let hailPayload = HitPayload(damage: hail, damageType: c.numbers.damageType, source: .skill(.skill1),
                                     skillID: skillID)
        let start = c.aim.direction.angle
        let hailVisual = Self.passiveVisual(ctx)
        for k in 0..<T.s1Hails {
            let angle = start + 2 * Double.pi * Double(k) / Double(T.s1Hails)
            let ring = T.s1Radius * (k % 2 == 0 ? T.hailRingInner : T.hailRingOuter)
            ZoneSystem.spawn(&s, ownerIndex: i, center: center + Vec2.fromAngle(angle) * ring, radius: T.hailRadius,
                             delay: T.s1Delay + T.hailGap + T.hailInterval * Double(k), payload: hailPayload,
                             visual: hailVisual)
        }
    }

    /// S2: 霜風（遅れて扇状に当たる。近すぎる敵は凍らない）と、扇の先の凍った地面。
    private func castBreeze(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        let skillID = c.check.skill.skillID
        s.units[i].hero!.kit!.oriaBreezeOrigin = origin
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * T.s2Range, shape: .fan, halfAngle: T.s2HalfAngle,
                     duration: T.s2Delay, count: 1)

        let wave = HitPayload(damage: c.numbers.damage, damageType: c.numbers.damageType, source: .skill(.skill2),
                              skillID: skillID, kitEvent: T.Event.breeze)
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin, radius: T.s2Range,
                         shape: .cone(direction: dir, halfAngle: T.s2HalfAngle), delay: T.s2Delay, payload: wave,
                         visual: c.check.skill.effectID)

        let tick = Self.patchTotal(c.numbers) / Double(T.s2PatchTicks)
        let patch = HitPayload(damage: tick, damageType: c.numbers.damageType, source: .skill(.skill2), skillID: skillID)
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin + dir * (T.s2Range - T.s2PatchBack),
                         radius: c.check.skill.radius, delay: T.s2Delay, duration: T.s2PatchDuration,
                         tickInterval: T.s2PatchInterval, payload: patch, visual: c.check.skill.effectID)
    }

    /// 奥義: 氷の道（貫通する弾。鈍足）と、道を覆う氷河（遅れて砕け、範囲の敵を凍結）。
    private func castGlacier(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        let origin = s.units[i].pos
        let dir = c.aim.direction
        let skillID = c.check.skill.skillID
        let visual = c.check.skill.effectID
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * T.ultRange, shape: .wideLine,
                     duration: T.ultGlacierDelay, count: 1)

        let slow = StatusEffect(kind: .slow, duration: T.ultPathSlowDuration, magnitude: T.ultPathSlow, sourceID: id,
                                tag: T.pathSlowTag)
        let path = HitPayload(damage: c.numbers.damage, damageType: c.numbers.damageType, source: .skill(.ultimate),
                              statuses: [slow], skillID: skillID)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: T.ultRange),
                               speed: T.ultPathSpeed, width: T.ultPathWidth, pierce: true, payload: path,
                               visual: visual)

        // 凍結の長さは発動時の魔力で決める（砕けるまでに魔力が変わっても、撃った時点の値）
        let freeze = StatusEffect(kind: .stun, duration: Self.glacierFreeze(abilityPower: s.units[i].stats.abilityPower),
                                  sourceID: id, tag: T.freezeTag)
        let shatter = HitPayload(damage: Self.shatterDamage(c.numbers), damageType: c.numbers.damageType,
                                 source: .skill(.ultimate), statuses: [freeze], skillID: skillID)
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin + dir * T.ultGlacierCenter, radius: T.ultGlacierRadius,
                         delay: T.ultGlacierDelay, payload: shatter, visual: visual)
    }

    /// 霜風の命中: 撃った位置から十分に離れた敵だけ凍結する。
    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard event == T.Event.breeze, let k = s.units[owner].hero?.kit, CombatSystem.isLiving(s, target),
              !s.units[target].isStructure else { return }
        guard k.oriaBreezeOrigin.distance(to: s.units[target].pos) >= T.s2FreezeMin else { return }
        let before = s.units[target].statuses.first { $0.kind == .stun && $0.tag == T.freezeTag }?.remaining ?? 0
        CombatSystem.addStatus(&s, targetIndex: target,
                               StatusEffect(kind: .stun, duration: T.s2Freeze, sourceID: s.units[owner].id,
                                            tag: T.freezeTag))
        let after = s.units[target].statuses.first { $0.kind == .stun && $0.tag == T.freezeTag }?.remaining ?? 0
        if after > before + 1e-9 {
            s.emit(.ccApplied(targetID: s.units[target].id, cc: .stun, duration: T.s2Freeze))
        }
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit, k.oriaHealTicks > 0 else { return }
        s.units[owner].hero!.kit!.oriaHealTicks = k.oriaHealTicks - 1
        // 回復阻害は受けるが、ヒーロー自身の回復強化・スコアには数えない（吸血と同じ扱い）
        CombatSystem.restoreHealth(&s, ctx, sourceID: s.units[owner].id, targetIndex: owner,
                                   amount: k.oriaHealPerTick, isVamp: true)
    }

    func onDeath(old: KitState, into fresh: inout KitState) {
        // 氷の誇りの再発動までの残りと、遅れて当たる霜風の起点は、死亡しても残る
        fresh.oriaPrideCooldown = old.oriaPrideCooldown
        fresh.oriaBreezeOrigin = old.oriaBreezeOrigin
    }

    // MARK: - C. パッシブ（氷の誇り）

    func modifyIncomingDamage(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                              source: DamageSource, amount: Double) -> Double {
        guard let k = s.units[victim].hero?.kit, k.oriaPrideCooldown <= CombatSystem.timeEpsilon, k.oriaFreezeLeft <= 0
        else { return amount }
        // 致命傷: シールドで受けきれず、HP が尽きる量
        guard amount - s.units[victim].totalShield >= s.units[victim].hp - CombatSystem.deathEpsilon else { return amount }
        beginPride(&s, ctx, victim)
        return 0
    }

    /// 致命傷を無効にして凍りつく: HP 1・シールドは失う・行動不能（suppress）+ 無敵・最大 HP の 30% を 1.5 秒かけて回復。
    private func beginPride(_ s: inout SimState, _ ctx: SimContext, _ i: Int) {
        let id = s.units[i].id
        s.units[i].hp = min(s.units[i].hp, 1)
        s.units[i].shields.removeAll()
        s.units[i].displacement = nil
        s.units[i].windupRemaining = nil
        // 先に行動不能（無敵のあいだは弱体を受け付けないため）、次に無敵
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .suppress, duration: T.prideFreeze, sourceID: id,
                                                                tag: T.prideSuppressTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .invulnerable, duration: T.prideFreeze,
                                                                sourceID: id, tag: T.prideInvulnerableTag))
        let ticks = Int((T.prideFreeze * Balance.tickRate).rounded())
        let noCooldowns = ctx.config.practice?.noCooldowns == true
        s.units[i].hero!.kit!.oriaSaves += 1
        s.units[i].hero!.kit!.oriaFreezeLeft = T.prideFreeze
        s.units[i].hero!.kit!.oriaHealTicks = ticks
        s.units[i].hero!.kit!.oriaHealPerTick = s.units[i].stats.maxHP * Self.prideHealRatio(level: s.units[i].hero?.level) / Double(ticks)
        s.units[i].hero!.kit!.oriaPrideCooldown = noCooldowns ? 0 : T.prideCooldown
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let dist = s.units[bot].pos.distance(to: s.units[target].pos)
        switch slot {
        case .skill2:
            // 凍結は離れた敵にだけ効く: 近すぎる相手には撃たない（扇に収まる距離のときだけ）
            guard dist >= T.s2FreezeMin + 20, dist <= T.s2Range - 30 else { return .skip }
            return .useDefault
        case .ultimate:
            guard fighting, dist <= T.ultRange - 60 else { return .skip }
            return .useDefault
        default:
            return .useDefault
        }
    }

    // MARK: - 部品

    /// 奥義の凍結秒: 1.0 秒 + 魔力 100 ごとに 0.2 秒（上限 +0.6 秒）。
    static func glacierFreeze(abilityPower: Double) -> Double {
        let bonus = min(T.ultFreezeMaxBonus, max(0, abilityPower) / 100 * T.ultFreezePerHundredAP)
        return T.ultFreeze + bonus
    }

    /// 氷の誇りの回復量（最大 HP の割合）: レベル 1 で prideHealLv1、最大レベルで prideHealRatio、間は線形。
    static func prideHealRatio(level: Int?) -> Double {
        let full = T.prideHealFullLevel
        let t = Double(min(max(1, level ?? full), full) - 1) / Double(max(1, full - 1))
        return T.prideHealLv1 + (T.prideHealRatio - T.prideHealLv1) * t
    }

    // 説明文の extras は整数に丸めて見せるので、実際のダメージは n.damage（丸めない）から比で求める。

    /// S1: 雹 1 発（n.damage は氷塊）。
    static func hailDamage(_ n: SkillNumbers) -> Double { n.damage / T.s1MeteorRatio * T.s1HailRatio }

    /// S2: 凍った地面の合計（n.damage は霜風）。
    static func patchTotal(_ n: SkillNumbers) -> Double { n.damage / T.s2HitRatio * T.s2PatchRatio }

    /// 奥義: 氷河が砕けるダメージ（n.damage は氷の道）。
    static func shatterDamage(_ n: SkillNumbers) -> Double { n.damage / T.ultPathRatio * T.ultShatterRatio }

    /// 雹・補助のゾーンに使う演出 ID（パッシブの演出 ID。氷塊・霜風・奥義の演出と重ねないため）。
    static func passiveVisual(_ ctx: SimContext) -> String {
        ctx.master.skill(hero: "H031", slot: .passive)?.effectID ?? ""
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、CD 短縮を掛ける（全体倍率 cooldownScale は 1.0 = MLBB の秒数のまま）。
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
}
