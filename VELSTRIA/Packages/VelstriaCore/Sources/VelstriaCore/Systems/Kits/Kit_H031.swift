import Foundation

// 担当: kit-H031（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Aurora.md）
// H031 氷嵐のオーリア = MLBB オーロラの Velstria 版（アルカニスト・遠隔 550・マナ）。
// 氷の魔導士。パッシブは「致命傷を受けると無効にして 1.5 秒凍りつく（無敵・最大 HP の 30% を少しずつ回復、CD 150 秒）」、
// S1 は地点に落ちる氷塊（鈍足）と続く 5 つの雹、S2 は遅れて広がる扇状の霜風（離れた敵を凍結）と扇の先の凍った地面、
// 奥義は前へ走る氷の道（大幅な鈍足）が氷河に育って砕け、範囲の敵を凍結する（魔力で凍結が延びる）。
// 対応表は docs/kits/Aurora.md の「Velstria 実装対応表」と「公式（現行シーズン）の数値」。
// 数値の換算（H029 ボルグと同じ方法）: 公式のダメージ表を Velstria のランク（スキル1・2 は 4 段、アルティメットは 3 段）へ線形補間し
//   （ランク 1 = Lv1、最大ランク = 公式の最終 Lv）、(基礎 + 係数 × 魔力) × スロット倍率 × スキルごとの換算（OriaTuning.*Scale）。
//   魔力の係数は公式の「+N% 魔法攻撃」そのまま（汎用の魔法スキルと同じく魔力に 1:1。物理攻撃では伸びない = 公式どおり）。
//   クールダウン・マナ消費の表もランクで補間する（マナは HeroKit.cost。クールダウンは公式の秒数そのまま）。

/// オーリアの調整値（docs/kits/Aurora.md の数値を Velstria の単位・TTK に合わせたもの）。
enum OriaTuning {
    // MARK: パッシブ（氷の誇り）
    static let prideFreeze: Double = 1.5
    /// 回復量（最大 HP の割合）は英雄のレベルで伸びる: Lv1 の prideHealLv1（0%）→ 最大レベル 15（prideHealFullLevel）で prideHealRatio（公式の 30%）。
    /// 氷の誇りは序盤ほど実質の耐久を大きく伸ばす（致命傷を 1 回無効にして 1.5 秒の無敵 + 回復）ため、総当たりの勝率が
    /// アルカニスト中央値より Lv1 で +59 pt（Lv6 +27 / Lv12 +19）と突出していた。回復を 5% にしても Lv1 は +45 pt 台に残る（無敵の 1.5 秒が効く）ので、
    /// Lv1 は回復なし（無敵の猶予のみ）とした。
    static let prideHealLv1: Double = 0.0
    static let prideHealRatio: Double = 0.30
    /// 回復量が公式の 30% に届くレベル（ゲームの最大レベル）。以前は 12 だったが、公式の表へ置き換えてスキル2 の CD が 13 → 8 秒になったぶん
    /// Lv12 の勝率がアルカニスト中央値 +27 pt に上がったので、最大レベルまで伸ばした（Lv12 は 23.6%。docs/kits/Aurora.md の「バランス」）。
    static let prideHealFullLevel = 15
    static let prideCooldown: Double = 150

    // MARK: S1（氷塊と雹）
    /// 公式: 氷塊 400 / 460 / 520 / 580 / 640 / 700（+90% 魔法攻撃）、雹 1 つ 40（全 Lv 一定。+10% 魔法攻撃）× 5。
    static let s1MeteorBase = (400.0, 700.0)
    static let s1MeteorPowerRatio: Double = 0.90
    static let s1HailBase = (40.0, 40.0)
    static let s1HailPowerRatio: Double = 0.10
    /// 公式の値 → Velstria の換算（氷塊と雹で共通）。氷塊 + 雹 5 発が全部 1 体に当たったときに汎用 S1 の 0.8〜1.3 倍に収まる値。
    static let s1Scale: Double = 0.29
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
    /// 公式: 霜風 225 / 255 / 285 / 315 / 345 / 375（+75% 魔法攻撃）、凍った地面の合計も同じ表（霜風 : 地面 = 1 : 1）。
    static let s2HitBase = (225.0, 375.0)
    static let s2HitPowerRatio: Double = 0.75
    static let s2PatchBase = (225.0, 375.0)
    static let s2PatchPowerRatio: Double = 0.75
    /// 公式の値 → Velstria の換算（霜風と地面で共通）。合計が汎用の元のスキル値（遠隔 S2 は「ブリンク + 強化攻撃」で半分なので
    /// base ÷ empowerRatio）の 0.8〜1.3 倍に収まる値。
    static let s2Scale: Double = 0.40
    static let s2Range: Double = 650
    /// 扇の半角（約 29°。全体で約 57°）。
    static let s2HalfAngle: Double = 0.65
    /// 霜風が広がるまでの遅れ（この間に避けられる）。
    static let s2Delay: Double = 0.3
    /// 凍結 1 秒 + 魔法攻撃 100 ごとに 0.06 秒（公式。上限の記載なし）。
    static let s2Freeze: Double = 1.0
    static let s2FreezePerHundredAP: Double = 0.06
    /// 術者からこれ未満の敵は凍らない（ダメージのみ。パッチ 1.8.56 の仕様）。
    static let s2FreezeMin: Double = 200
    /// 凍った地面: 扇の先、中心は術者から range − patchBack の位置。
    static let s2PatchBack: Double = 110
    static let s2PatchDuration: Double = 1.8
    static let s2PatchInterval: Double = 0.5
    /// 凍った地面が当てる回数（発動 + 以降の間隔ごと = 4 回。合計が公式の凍った地面の表）。
    static let s2PatchTicks = 4

    // MARK: 奥義（氷河）
    /// 公式: 氷の道 100 / 150 / 200（+40% 魔法攻撃）、氷河の砕け 600 / 900 / 1200（+150% 魔法攻撃）。
    static let ultPathBase = (100.0, 200.0)
    static let ultPathPowerRatio: Double = 0.40
    static let ultShatterBase = (600.0, 1200.0)
    static let ultShatterPowerRatio: Double = 1.50
    /// 公式の値 → Velstria の換算（道と砕けで共通）。道 + 砕けは汎用の奥義の 0.66〜0.90 倍（ランク 1 は予算の下限 0.8 を割る）:
    /// 公式の表はランク 1 → 3 で 2 倍に伸び（汎用は 1.6 倍）、氷の誇り（実質の耐久 +45%）もあるため、Lv12 の勝率で決めた値。
    static let ultScale: Double = 0.36
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
    /// 魔法攻撃 100 ごとに凍結が延びる秒数（公式。上限の記載なし。以前は +0.6 秒の上限を足していた）。
    static let ultFreezePerHundredAP: Double = 0.2

    // MARK: クールダウン（公式の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
    /// 現行: S1 6.0 → 4.0 / S2 12.0 → 8.0 / 奥義 50 / 45 / 40 秒（以前は S2 をヒーローページの 13 秒固定にしていた）。
    static let s1Cooldown = (6.0, 4.0)
    static let s2Cooldown = (12.0, 8.0)
    static let ultCooldown = (50.0, 40.0)
    // MARK: マナ消費（公式。ランクで補間して整数に丸める）
    static let s1Cost = (60.0, 85.0)
    static let s2Cost = (75.0, 100.0)
    static let ultCost = (140.0, 180.0)

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

    /// 霜風の凍結秒（撃った時点の魔力で決める。1 秒 + 魔法攻撃 100 ごとに 0.06 秒）。0 = 未設定（1 秒として扱う）。
    var oriaBreezeFreeze: Double {
        get { reals[3] }
        set { reals[3] = newValue }
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
            n.damage = Self.meteorDamage(rank: rank, stats: stats)
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccIsUltimate = false
            n.ccDuration = T.s1SlowDuration
            n.delay = T.s1Delay
            n.extras = [KitStat(key: "slow", value: T.s1Slow * 100),
                        KitStat(key: "slowDuration", value: T.s1SlowDuration),
                        KitStat(key: "hails", value: Double(T.s1Hails)),
                        KitStat(key: "hailDamage", value: Self.hailDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "meteorBase", value: Self.scaledBase(T.s1MeteorBase, slot: .skill1, scale: T.s1Scale,
                                                                          rank: rank).rounded()),
                        KitStat(key: "meteorPct", value: Self.powerPercent(T.s1MeteorPowerRatio, slot: .skill1,
                                                                           scale: T.s1Scale).rounded()),
                        KitStat(key: "hailBase", value: Self.scaledBase(T.s1HailBase, slot: .skill1, scale: T.s1Scale,
                                                                        rank: rank).rounded()),
                        KitStat(key: "hailPct", value: Self.powerPercent(T.s1HailPowerRatio, slot: .skill1,
                                                                         scale: T.s1Scale).rounded())]
        case .skill2:
            n.damage = Self.breezeDamage(rank: rank, stats: stats)
            n.cooldown = Self.cooldown(T.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = false
            n.ccDuration = Self.breezeFreeze(abilityPower: stats.abilityPower)
            n.delay = T.s2Delay
            n.extras = [KitStat(key: "freeze", value: Self.breezeFreeze(abilityPower: stats.abilityPower)),
                        KitStat(key: "patchDuration", value: T.s2PatchDuration),
                        KitStat(key: "patchTotal", value: Self.patchTotal(rank: rank, stats: stats).rounded()),
                        KitStat(key: "freezeMin", value: T.s2FreezeMin),
                        KitStat(key: "hitBase", value: Self.scaledBase(T.s2HitBase, slot: .skill2, scale: T.s2Scale,
                                                                       rank: rank).rounded()),
                        KitStat(key: "hitPct", value: Self.powerPercent(T.s2HitPowerRatio, slot: .skill2,
                                                                        scale: T.s2Scale).rounded()),
                        KitStat(key: "patchBase", value: Self.scaledBase(T.s2PatchBase, slot: .skill2, scale: T.s2Scale,
                                                                         rank: rank).rounded()),
                        KitStat(key: "patchPct", value: Self.powerPercent(T.s2PatchPowerRatio, slot: .skill2,
                                                                          scale: T.s2Scale).rounded())]
        case .ultimate:
            n.damage = Self.pathDamage(rank: rank, stats: stats)
            n.cooldown = Self.cooldown(T.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Self.glacierFreeze(abilityPower: stats.abilityPower)
            n.delay = T.ultGlacierDelay
            n.extras = [KitStat(key: "slow", value: T.ultPathSlow * 100),
                        KitStat(key: "slowDuration", value: T.ultPathSlowDuration),
                        KitStat(key: "shatterDamage", value: Self.shatterDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "freeze", value: Self.glacierFreeze(abilityPower: stats.abilityPower)),
                        KitStat(key: "pathBase", value: Self.scaledBase(T.ultPathBase, slot: .ultimate, scale: T.ultScale,
                                                                        rank: rank).rounded()),
                        KitStat(key: "pathPct", value: Self.powerPercent(T.ultPathPowerRatio, slot: .ultimate,
                                                                         scale: T.ultScale).rounded()),
                        KitStat(key: "shatterBase", value: Self.scaledBase(T.ultShatterBase, slot: .ultimate,
                                                                           scale: T.ultScale, rank: rank).rounded()),
                        KitStat(key: "shatterPct", value: Self.powerPercent(T.ultShatterPowerRatio, slot: .ultimate,
                                                                            scale: T.ultScale).rounded())]
        }
        return n
    }

    /// ランクごとのマナ消費（公式: スキル1 60 → 85、スキル2 75 → 100、アルティメット 140 / 160 / 180。補間した値を整数に丸める）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: (Double, Double)
        switch slot {
        case .skill1: table = T.s1Cost
        case .skill2: table = T.s2Cost
        case .ultimate: table = T.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Self.lerp(table.0, table.1, rank: rank, maxRank: slot.maxRank).rounded(), hero: hero)
    }

    /// 説明文は公式の文の構造に合わせる（数値は {トークン} で sim から。{xBase}(+{xPct}%魔法攻撃) は sim の式に換算した値）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "致命的なダメージを受けると、{freeze}秒間自身を凍結させる。その間は無敵となり、最大HPを徐々に回復する"
                    + "（回復量はレベルで伸び、レベル1で{healMin}%、レベル\(T.prideHealFullLevel)以降で{x1}%）。この効果のクールダウンは{cooldown}秒。"
                    + "\n\n致命的なダメージは無効になり、復活系の装備より先に発動する。凍結中は行動できない。",
                en: "Upon taking fatal damage, freeze yourself for {freeze}s, becoming invincible during this time and gradually recovering Max HP "
                    + "(the amount grows with level: {healMin}% at level 1, {x1}% from level \(T.prideHealFullLevel)). This effect has a {cooldown}s cooldown."
                    + "\n\nThe fatal damage is negated, and this triggers before revival items. You cannot act while frozen.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "指定地点に氷塊を落とし、{meteorBase}(+{meteorPct}%魔法攻撃)の魔法ダメージを与えて、命中した敵の移動速度を{slowDuration}秒間{slow}%低下させる。"
                    + "その後、{hails}個の雹が降り注ぎ、それぞれ{hailBase}(+{hailPct}%魔法攻撃)の魔法ダメージを与える（雹は氷塊の中心を外れたまわりに降る）。",
                en: "Summon an icy meteorite to strike the target location, dealing {meteorBase} (+{meteorPct}% Magic Power) magic damage and slowing targets hit by {slow}% for {slowDuration}s. "
                    + "Afterward, {hails} hailstones fall, each dealing {hailBase} (+{hailPct}% Magic Power) magic damage (they land around the meteorite, just off its center).",
                tags: [KitTag.aoe, KitTag.slow])
        case .skill2:
            return KitText(
                ja: "指定方向の扇形範囲に霜風を吹きつけ、命中した敵に{hitBase}(+{hitPct}%魔法攻撃)の魔法ダメージを与えて{freeze}秒間凍結させる（自分のすぐ近くの敵は凍結しない）。"
                    + "さらに攻撃の先端に凍った地面を作り、{patchDuration}秒間で範囲内の敵に合計{patchBase}(+{patchPct}%魔法攻撃)の魔法ダメージを与える。"
                    + "魔法攻撃100ごとに凍結時間が\(Self.seconds(T.s2FreezePerHundredAP))秒延びる。",
                en: "Blow Frosty Breeze in a fan-shaped area in the target direction, dealing {hitBase} (+{hitPct}% Magic Power) magic damage to enemies hit and freezing them for {freeze}s (enemies right next to you are not frozen). "
                    + "A frozen area is created at the far end of the attack, dealing a total of {patchBase} (+{patchPct}% Magic Power) magic damage to enemies in it over {patchDuration}s. "
                    + "Every 100 Magic Power adds \(Self.seconds(T.s2FreezePerHundredAP))s to the freeze.",
                tags: [KitTag.aoe, KitTag.control])
        case .ultimate:
            return KitText(
                ja: "指定方向に氷の道を作り、道の上の敵に{pathBase}(+{pathPct}%魔法攻撃)の魔法ダメージを与えて、移動速度を{slowDuration}秒間{slow}%低下させる。"
                    + "氷の道はしだいに氷河となって最大まで広がったのち砕け、範囲内のすべての敵に{shatterBase}(+{shatterPct}%魔法攻撃)の魔法ダメージを与えて{freeze}秒間凍結させる。"
                    + "魔法攻撃100ごとに凍結時間が\(Self.seconds(T.ultFreezePerHundredAP))秒延びる。",
                en: "Create a frost path in the target direction, dealing {pathBase} (+{pathPct}% Magic Power) magic damage to enemies in the path and reducing their Movement Speed by {slow}% for {slowDuration}s. "
                    + "The frost path gradually becomes glaciers that spread to their maximum size and shatter, dealing {shatterBase} (+{shatterPct}% Magic Power) magic damage to all enemies in the area and freezing them for {freeze}s. "
                    + "Every 100 Magic Power adds \(Self.seconds(T.ultFreezePerHundredAP))s to the freeze.",
                tags: [KitTag.control, KitTag.aoe])
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
        let hail = Self.hailDamage(rank: c.numbers.rank, stats: s.units[i].stats)
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
        s.units[i].hero!.kit!.oriaBreezeFreeze = Self.breezeFreeze(abilityPower: s.units[i].stats.abilityPower)
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * T.s2Range, shape: .fan, halfAngle: T.s2HalfAngle,
                     duration: T.s2Delay, count: 1)

        let wave = HitPayload(damage: c.numbers.damage, damageType: c.numbers.damageType, source: .skill(.skill2),
                              skillID: skillID, kitEvent: T.Event.breeze)
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin, radius: T.s2Range,
                         shape: .cone(direction: dir, halfAngle: T.s2HalfAngle), delay: T.s2Delay, payload: wave,
                         visual: c.check.skill.effectID)

        let tick = Self.patchTotal(rank: c.numbers.rank, stats: s.units[i].stats) / Double(T.s2PatchTicks)
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
        let shatter = HitPayload(damage: Self.shatterDamage(rank: c.numbers.rank, stats: s.units[i].stats),
                                 damageType: c.numbers.damageType,
                                 source: .skill(.ultimate), statuses: [freeze], skillID: skillID)
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin + dir * T.ultGlacierCenter, radius: T.ultGlacierRadius,
                         delay: T.ultGlacierDelay, payload: shatter, visual: visual)
    }

    /// 霜風の命中: 撃った位置から十分に離れた敵だけ凍結する（1 秒 + 魔法攻撃 100 ごとに 0.06 秒。撃った時点の魔力）。
    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard event == T.Event.breeze, let k = s.units[owner].hero?.kit, CombatSystem.isLiving(s, target),
              !s.units[target].isStructure else { return }
        guard k.oriaBreezeOrigin.distance(to: s.units[target].pos) >= T.s2FreezeMin else { return }
        let duration = k.oriaBreezeFreeze > 0 ? k.oriaBreezeFreeze : T.s2Freeze
        let before = s.units[target].statuses.first { $0.kind == .stun && $0.tag == T.freezeTag }?.remaining ?? 0
        CombatSystem.addStatus(&s, targetIndex: target,
                               StatusEffect(kind: .stun, duration: duration, sourceID: s.units[owner].id,
                                            tag: T.freezeTag))
        let after = s.units[target].statuses.first { $0.kind == .stun && $0.tag == T.freezeTag }?.remaining ?? 0
        if after > before + 1e-9 {
            s.emit(.ccApplied(targetID: s.units[target].id, cc: .stun, duration: duration))
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
        fresh.oriaBreezeFreeze = old.oriaBreezeFreeze
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

    /// 奥義の凍結秒: 1.0 秒 + 魔法攻撃 100 ごとに 0.2 秒（公式。上限なし）。
    static func glacierFreeze(abilityPower: Double) -> Double {
        T.ultFreeze + max(0, abilityPower) / 100 * T.ultFreezePerHundredAP
    }

    /// スキル2 の凍結秒: 1.0 秒 + 魔法攻撃 100 ごとに 0.06 秒（公式。上限なし）。
    static func breezeFreeze(abilityPower: Double) -> Double {
        T.s2Freeze + max(0, abilityPower) / 100 * T.s2FreezePerHundredAP
    }

    /// 氷の誇りの回復量（最大 HP の割合）: レベル 1 で prideHealLv1、最大レベルで prideHealRatio、間は線形。
    static func prideHealRatio(level: Int?) -> Double {
        let full = T.prideHealFullLevel
        let t = Double(min(max(1, level ?? full), full) - 1) / Double(max(1, full - 1))
        return T.prideHealLv1 + (T.prideHealRatio - T.prideHealLv1) * t
    }

    // 説明文の extras は整数に丸めて見せるので、実際のダメージはランクと能力値から丸めずに求める。

    /// 公式の基礎ダメージ（ランクで補間）を sim の通常の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), slot: SkillSlot, scale: Double, rank: Int) -> Double {
        lerp(table.0, table.1, rank: rank, maxRank: slot.maxRank) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の「+N% 魔法攻撃」を sim の式（× スロット倍率 × 換算）に通した、魔力に対する割合（%）。
    static func powerPercent(_ ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * Balance.Skills.damageScale(slot) * scale * 100
    }

    /// (公式の基礎 + 係数 × 魔力) × スロット倍率 × 換算。
    private static func damage(_ base: (Double, Double), ratio: Double, slot: SkillSlot, scale: Double, rank: Int,
                               stats: Stats) -> Double {
        (lerp(base.0, base.1, rank: rank, maxRank: slot.maxRank) + ratio * max(0, stats.abilityPower))
            * Balance.Skills.damageScale(slot) * scale
    }

    /// S1: 氷塊（400 → 700 + 90% 魔法攻撃）。
    static func meteorDamage(rank: Int, stats: Stats) -> Double {
        damage(T.s1MeteorBase, ratio: T.s1MeteorPowerRatio, slot: .skill1, scale: T.s1Scale, rank: rank, stats: stats)
    }

    /// S1: 雹 1 発（40 + 10% 魔法攻撃）。
    static func hailDamage(rank: Int, stats: Stats) -> Double {
        damage(T.s1HailBase, ratio: T.s1HailPowerRatio, slot: .skill1, scale: T.s1Scale, rank: rank, stats: stats)
    }

    /// S2: 霜風（225 → 375 + 75% 魔法攻撃）。
    static func breezeDamage(rank: Int, stats: Stats) -> Double {
        damage(T.s2HitBase, ratio: T.s2HitPowerRatio, slot: .skill2, scale: T.s2Scale, rank: rank, stats: stats)
    }

    /// S2: 凍った地面の合計（225 → 375 + 75% 魔法攻撃）。
    static func patchTotal(rank: Int, stats: Stats) -> Double {
        damage(T.s2PatchBase, ratio: T.s2PatchPowerRatio, slot: .skill2, scale: T.s2Scale, rank: rank, stats: stats)
    }

    /// 奥義: 氷の道（100 / 150 / 200 + 40% 魔法攻撃）。
    static func pathDamage(rank: Int, stats: Stats) -> Double {
        damage(T.ultPathBase, ratio: T.ultPathPowerRatio, slot: .ultimate, scale: T.ultScale, rank: rank, stats: stats)
    }

    /// 奥義: 氷河が砕けるダメージ（600 / 900 / 1200 + 150% 魔法攻撃）。
    static func shatterDamage(rank: Int, stats: Stats) -> Double {
        damage(T.ultShatterBase, ratio: T.ultShatterPowerRatio, slot: .ultimate, scale: T.ultScale, rank: rank,
               stats: stats)
    }

    /// 説明文に埋める秒数（0.06 のような小数 2 桁も落とさない）。
    static func seconds(_ v: Double) -> String { String(format: "%g", v) }

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
