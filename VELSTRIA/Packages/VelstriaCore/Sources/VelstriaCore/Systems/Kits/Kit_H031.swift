import Foundation

// 担当: kit-H031（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Aurora.md）
// H031 氷嵐のオーリア = MLBB オーロラの Velstria 版（アルカニスト・遠隔 470（MLBB の 4.7）・マナ）。
// 氷の魔導士。パッシブは「致命傷を受けると無効にして 1.5 秒凍りつく（無敵・最大 HP の 30% を少しずつ回復、CD 150 秒）」、
// S1 は地点に落ちる氷の隕石（鈍足）と、同じ円に続けて降る 5 つの雹、S2 は扇状の霜風と扇の先の半分の凍結エリア（エリア内の敵を凍結）、
// 奥義は前へ伸びる霜の道（大幅な鈍足）が帯の氷河に育って砕け、範囲の敵を凍結する（魔力で凍結が延びる）。
// 凍結エリア・砕けの凍結は敵のタワーにも効く（凍ったタワーは攻撃しない。ダメージは与えない。freezeTurret）。
// 対応表は docs/kits/Aurora.md の「Velstria 実装対応表」と「日本語クライアントの画面」。幾何と時間は「動画で測った値（2026-10-16）」。
// 数値は公式の表をそのまま使う（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3 の 6 / 6 / 3 段。rank = 公式の Lv。換算・補間なし）:
//   ダメージ = 公式の基礎[段] + 公式の係数 × 魔法攻撃（Kit.official。物理攻撃では伸びない = 公式どおり）、
//   CD = 公式の秒数 × (1 − CD 短縮)（Kit.cooldown）、マナ = 公式の表（HeroKit.cost）。
// スキル吸収率・ミニオン / モンスターへの補正は公式の文に無いので既定（100%・等倍）。

/// オーリアの数値（docs/kits/Aurora.md の「日本語クライアントの画面」の表そのまま）。
/// 射程・半径・遅れ・持続・雹の間隔など、公式の文に無い幾何と時間は MLBB の訓練場の画面収録で測った値
/// （docs の「動画で測った値（2026-10-16）」。距離 = MLBB × 100、時間はコマ（1/30 秒）を tick に合わせた値）。
enum OriaTuning {
    // MARK: パッシブ（プライド・オブ・アイス）
    /// 公式: 致命的なダメージで 1.5 秒間フリーズ（無敵）、最大 HP の 30% を徐々に回復（全レベル一定）、CD 150 秒。
    static let prideFreeze: Double = 1.5
    static let prideHealRatio: Double = 0.30
    static let prideCooldown: Double = 150

    // MARK: S1（雪華の烈風: 氷の隕石と雹）
    /// 公式: 氷の隕石 400 / 460 / 520 / 580 / 640 / 700（+90% 魔法攻撃）、雹 1 つ 40（全 Lv 一定。+10% 魔法攻撃）× 5。
    static let s1MeteorBase: [Double] = [400, 460, 520, 580, 640, 700]
    static let s1MeteorPowerRatio: Double = 0.90
    static let s1HailBase: [Double] = [40]
    static let s1HailPowerRatio: Double = 0.10
    static let s1Hails = 5
    /// 射程（動画: 照準の円の半径 5.56。2 回の照準で 5.557 / 5.565）。隕石の中心はこの距離まで。
    static let s1Range: Double = 556
    /// 隕石の半径（動画: 着弾点の照準の円 1.903〜1.913。縁 1.85 の的にも当たった）。
    static let s1Radius: Double = 191
    /// 指を離してから隕石が落ちるまで（動画: 16 / 18 コマ = 平均 17 コマ ≒ 0.57 秒。0.56 で 17 tick 目に落ちる）。
    static let s1Delay: Double = 0.56
    static let s1Slow: Double = 0.40
    /// 減速の長さ（公式 1 秒。動画: 的の移動速度の表示 159 が 33 コマ = 表示の遅れ込みで 1 秒と合う。雹では掛け直さない）。
    static let s1SlowDuration: Double = 1.0
    /// 雹: 隕石と同じ円（中心・半径 s1Radius）に降り、降るたびに円の中の敵全員に当たる（動画: 円の中心から 0.70 と縁の 1.85 に
    /// 立つ 2 体が 5 発とも受けた。雹の氷が落ちる位置はばらばらだが、当たりは円全体）。
    /// 隕石から最初の雹まで（動画: 14 / 15 コマ）と、雹の間隔（動画: 5 発が 17 コマに並ぶ = 0.15 秒おき）。
    /// tick に合わせると隕石の後 0.47 / 0.63 / 0.77 / 0.93 / 1.07 秒（ゾーンの tickInterval 0.15 の積み上げ）。
    static let hailGap: Double = 0.47
    static let hailInterval: Double = 0.15

    // MARK: S2（氷花のそよ風: 霜風と凍結エリア）
    /// 公式: 扇の霜風 225 / 255 / 285 / 315 / 345 / 375（+75% 魔法攻撃）。範囲の末端に凍結エリアを作り、
    /// エリア内の敵に合計 225 → 375（+75% 魔法攻撃。霜風と同じ表）、1 秒フリーズ（魔法攻撃 100 ごとに +0.06 秒）。
    static let s2HitBase: [Double] = [225, 255, 285, 315, 345, 375]
    static let s2HitPowerRatio: Double = 0.75
    static let s2PatchBase: [Double] = [225, 255, 285, 315, 345, 375]
    static let s2PatchPowerRatio: Double = 0.75
    /// 扇の半径（動画: 照準の扇の弧 6.02。弧の中心は術者）。
    static let s2Range: Double = 602
    /// 扇の半角（動画: 照準の左右の辺の開き 50.5° = 片側 25.3°。辺は術者の位置を通る）。
    static let s2HalfAngle: Double = 0.441
    /// 指を離してから霜風が当たるまで（動画: 17 コマ ≒ 0.57 秒。中心から 3.8 と 4.4 の 2 体に同じコマで当たった。0.56 で 17 tick 目）。
    static let s2Delay: Double = 0.56
    /// 凍結 1 秒 + 魔法攻撃 100 ごとに 0.06 秒（公式。上限の記載なし）。凍結は凍結エリアでだけ（扇の霜風はダメージだけ）。
    /// 動画: 霜風のダメージのコマでは凍らず、5 コマ後の凍結エリアの 1 回目で「凍結」の表示（32 コマ = 表示の遅れ込みで 1 秒）。
    static let s2Freeze: Double = 1.0
    static let s2FreezePerHundredAP: Double = 0.06
    /// 凍結エリア = 扇の先の半分（動画: 霜風の後に残る氷の地面は術者から 2.9〜6.0、扇と同じ角度）。
    /// 術者から s2AreaInner より内側（対象の半径を足しても届かない敵）は凍らない（霜風のダメージだけ）。
    static let s2AreaInner: Double = 290
    /// 指を離してから凍結エリアができるまで（動画: 23 コマ ≒ 0.77 秒 = 霜風の 0.2 秒後。0.76 で 23 tick 目）。
    static let s2AreaDelay: Double = 0.76
    /// 凍結エリアの持続・ダメージの間隔（動画: 的の合計ダメージの表示が 4 コマおきに 3 回増えた = 0.13 秒おきに 3 回）。
    /// 凍結はエリアができた瞬間（最初の適用）にエリア内にいる敵だけに 1 回。氷の地面の見た目は 0.6 秒ほど残る（当たりは 0.26 秒）。
    static let s2PatchDuration: Double = 0.26
    static let s2PatchInterval: Double = 0.13
    /// 凍結エリアが当てる回数（発動 + 以降の間隔ごと = 3 回。合計が公式の凍結エリアの表。動画: 1 回 = 霜風の 1/3）。
    static let s2PatchTicks = 3

    // MARK: 奥義（凍てつく氷結: 霜の道と氷河）
    /// 公式: 霜の道 100 / 150 / 200（+40% 魔法攻撃）、氷河の砕け 600 / 900 / 1200（+150% 魔法攻撃）。
    static let ultPathBase: [Double] = [100, 150, 200]
    static let ultPathPowerRatio: Double = 0.40
    static let ultShatterBase: [Double] = [600, 900, 1200]
    static let ultShatterPowerRatio: Double = 1.50
    /// 霜の道の先端（術者から。動画: 照準の矢の先 6.8、道の氷は 7.1 まで）。
    static let ultRange: Double = 680
    /// 霜の道・氷河は術者の少し後ろから始まる（動画: 道の氷・氷河の後ろの端は術者の 0.7 後ろ）。
    static let ultBack: Double = 70
    /// 指を離してから霜の道ができるまで（動画: 8 コマ ≒ 0.27 秒。道は 1〜2 コマで先まで伸びる = ほぼ一度に当たる。0.26 で 8 tick 目）。
    static let ultPathDelay: Double = 0.26
    /// 霜の道の半幅（当たり幅。動画: 照準の内側の 2 本の線の間 0.95 = 半幅 0.48）。
    static let ultPathWidth: Double = 48
    static let ultPathSlow: Double = 0.80
    static let ultPathSlowDuration: Double = 1.2
    /// 氷河 = 道に沿った帯（長方形）。最大のときの前の端（術者から）と半幅（動画: 砕ける直前の氷河の外形 −0.7〜6.2 × ±2.45、
    /// 照準の外側の 2 本の線 ±2.5）。Fandom の「7.5 × 7 マス」より細い。
    static let ultGlacierLength: Double = 620
    static let ultGlacierHalfWidth: Double = 245
    /// 指を離してから砕けるまで（動画: 45 コマ ≒ 1.5 秒。氷河は道ができた 0.27 秒から育ち、1.45 秒ごろ最大。1.49 で 45 tick 目）。
    static let ultGlacierDelay: Double = 1.49
    static let ultFreeze: Double = 1.0
    /// 魔法攻撃 100 ごとに凍結が延びる秒数（公式。上限の記載なし）。
    static let ultFreezePerHundredAP: Double = 0.2

    // MARK: クールダウン・マナ消費（日本語クライアントの表そのまま。CD には CD 短縮を掛ける）
    static let s1Cooldown: [Double] = [5.0, 4.8, 4.6, 4.4, 4.2, 4.0]
    static let s2Cooldown: [Double] = [10.0, 9.6, 9.2, 8.8, 8.4, 8.0]
    static let ultCooldown: [Double] = [50, 45, 40]
    static let s1Cost: [Double] = [60, 65, 70, 75, 80, 85]
    static let s2Cost: [Double] = [75, 80, 85, 90, 95, 100]
    static let ultCost: [Double] = [140, 160, 180]

    // MARK: タグ・コード
    static let s1SlowTag = KitTags.buff("H031", "hailSlow")
    static let freezeTag = KitTags.buff("H031", "freeze")
    static let pathSlowTag = KitTags.buff("H031", "pathSlow")
    static let prideSuppressTag = KitTags.buff("H031", "prideFreeze")
    static let prideInvulnerableTag = KitTags.buff("H031", "prideGuard")

    /// KitTimer.code
    enum Code {
        /// 霜の道（ultPathDelay の後に、撃った位置・向きの帯の敵へ当たる。スタンでは取り消さない）。
        static let path = 1
    }

    /// HitPayload.kitEvent
    enum Event {
        /// スキル2 の凍結エリア（できた瞬間にエリア内の敵・敵のタワーを凍結する。以降の適用はダメージだけ）。
        static let frozenArea = 1
        /// 氷河の砕け（敵の構造物を凍らせるためだけ。ヒーロー・ミニオンの凍結は payload の statuses）。
        static let shatter = 2
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

    /// 凍結エリアの凍結秒（撃った時点の魔力で決める。1 秒 + 魔法攻撃 100 ごとに 0.06 秒）。0 = 未設定（1 秒として扱う）。
    var oriaAreaFreeze: Double {
        get { reals[3] }
        set { reals[3] = newValue }
    }

    /// 氷河の凍結秒（発動時の魔力で決める。敵の構造物を凍らせるときに使う）。0 = 未設定（1 秒として扱う）。
    var oriaGlacierFreeze: Double {
        get { reals[4] }
        set { reals[4] = newValue }
    }

    /// 霜の道のダメージ（撃った時点の段と魔力。ultPathDelay の後のタイマーで当てる）。
    var oriaPathDamage: Double {
        get { reals[5] }
        set { reals[5] = newValue }
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
            // 地点指定の氷の隕石（HUD は地点の円、ボットは地点 AoE として狙う）
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: T.s1Range, radius: T.s1Radius,
                                  shape: .circleAtPoint)
        case .skill2:
            // 扇状の霜風（radius = 扇の半径）
            return SkillTargeting(archetype: .cone, aim: .direction, range: T.s2Range, radius: T.s2Range,
                                  shape: .fan, halfAngle: T.s2HalfAngle)
        case .ultimate:
            // 照準の帯の半幅 = 氷河の半幅（氷河が砕けて凍らせる範囲。霜の道そのものの当たり幅は T.ultPathWidth で別）
            return SkillTargeting(archetype: .piercingLine, aim: .direction, range: T.ultRange, radius: T.ultGlacierHalfWidth,
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
                        KitStat(key: "cooldown", value: T.prideCooldown)]
        case .skill1:
            n.damage = Self.meteorDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(T.s1Cooldown, rank: rank, stats: stats)
            n.cc = .slow
            n.ccIsUltimate = false
            n.ccDuration = T.s1SlowDuration
            n.delay = T.s1Delay
            n.extras = [KitStat(key: "slow", value: T.s1Slow * 100),
                        KitStat(key: "slowDuration", value: T.s1SlowDuration),
                        KitStat(key: "hails", value: Double(T.s1Hails)),
                        KitStat(key: "hailDamage", value: Self.hailDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "meteorBase", value: Kit.level(T.s1MeteorBase, rank: rank)),
                        KitStat(key: "meteorPct", value: (T.s1MeteorPowerRatio * 100).rounded()),
                        KitStat(key: "hailBase", value: Kit.level(T.s1HailBase, rank: rank)),
                        KitStat(key: "hailPct", value: (T.s1HailPowerRatio * 100).rounded())]
        case .skill2:
            n.damage = Self.breezeDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(T.s2Cooldown, rank: rank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = false
            n.ccDuration = Self.breezeFreeze(abilityPower: stats.abilityPower)
            n.delay = T.s2Delay
            n.extras = [KitStat(key: "freeze", value: Self.breezeFreeze(abilityPower: stats.abilityPower)),
                        KitStat(key: "patchDuration", value: T.s2PatchDuration),
                        KitStat(key: "patchTotal", value: Self.patchTotal(rank: rank, stats: stats).rounded()),
                        KitStat(key: "hitBase", value: Kit.level(T.s2HitBase, rank: rank)),
                        KitStat(key: "hitPct", value: (T.s2HitPowerRatio * 100).rounded()),
                        KitStat(key: "patchBase", value: Kit.level(T.s2PatchBase, rank: rank)),
                        KitStat(key: "patchPct", value: (T.s2PatchPowerRatio * 100).rounded())]
        case .ultimate:
            n.damage = Self.pathDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(T.ultCooldown, rank: rank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Self.glacierFreeze(abilityPower: stats.abilityPower)
            n.delay = T.ultGlacierDelay
            n.extras = [KitStat(key: "slow", value: T.ultPathSlow * 100),
                        KitStat(key: "slowDuration", value: T.ultPathSlowDuration),
                        KitStat(key: "shatterDamage", value: Self.shatterDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "freeze", value: Self.glacierFreeze(abilityPower: stats.abilityPower)),
                        KitStat(key: "pathBase", value: Kit.level(T.ultPathBase, rank: rank)),
                        KitStat(key: "pathPct", value: (T.ultPathPowerRatio * 100).rounded()),
                        KitStat(key: "shatterBase", value: Kit.level(T.ultShatterBase, rank: rank)),
                        KitStat(key: "shatterPct", value: (T.ultShatterPowerRatio * 100).rounded())]
        }
        return n
    }

    /// 段ごとのマナ消費（公式の表: スキル1 60〜85、スキル2 75〜100、アルティメット 140 / 160 / 180）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: [Double]
        switch slot {
        case .skill1: table = T.s1Cost
        case .skill2: table = T.s2Cost
        case .ultimate: table = T.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Kit.level(table, rank: rank), hero: hero)
    }

    /// 説明文は公式の文の構造に合わせる（数値は {トークン} で sim から。{xBase}(+{xPct}%魔法攻撃) は公式の値そのもの）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "致命的なダメージを受けると、{freeze}秒間自身を凍結させる。その間は無敵となり、最大HPの{x1}%を徐々に回復する。"
                    + "この効果のクールダウンは{cooldown}秒。"
                    + "\n\n致命的なダメージは無効になり、復活系の装備より先に発動する。凍結中は行動できない。"
                    + "\n\n自身の凍結効果はタワーにも効く（凍ったタワーは攻撃しない）。",
                en: "Upon taking fatal damage, freeze yourself for {freeze}s, becoming invincible during this time and gradually recovering {x1}% Max HP. "
                    + "This effect has a {cooldown}s cooldown."
                    + "\n\nThe fatal damage is negated, and this triggers before revival items. You cannot act while frozen."
                    + "\n\nYour freeze effects also affect turrets (a frozen turret does not attack).",
                tags: [KitTag.deathImmunity])
        case .skill1:
            return KitText(
                ja: "指定地点に氷の隕石を落とし、{meteorBase}(+{meteorPct}%魔法攻撃)の魔法ダメージを与えて、命中した敵の移動速度を{slowDuration}秒間{slow}%低下させる。"
                    + "その後、{hails}個の雹が降り注ぎ、それぞれ{hailBase}(+{hailPct}%魔法攻撃)の魔法ダメージを与える（雹は隕石と同じ範囲に降る）。",
                en: "Summon an icy meteorite to strike the target location, dealing {meteorBase} (+{meteorPct}% Magic Power) magic damage and slowing targets hit by {slow}% for {slowDuration}s. "
                    + "Afterward, {hails} hailstones fall, each dealing {hailBase} (+{hailPct}% Magic Power) magic damage (they fall over the same area as the meteorite).",
                tags: [KitTag.aoe, KitTag.slow])
        case .skill2:
            return KitText(
                ja: "指定方向の扇形範囲に霜風を吹きつけ、命中した敵に{hitBase}(+{hitPct}%魔法攻撃)の魔法ダメージを与える。"
                    + "さらに攻撃の末端に凍結エリアを作り、エリア内の敵を{freeze}秒間凍結させて、{patchDuration}秒間で合計{patchBase}(+{patchPct}%魔法攻撃)の魔法ダメージを与える。"
                    + "魔法攻撃100ごとに凍結時間が\(Self.seconds(T.s2FreezePerHundredAP))秒延びる。",
                en: "Blow Frosty Breeze in a fan-shaped area in the target direction, dealing {hitBase} (+{hitPct}% Magic Power) magic damage to enemies hit. "
                    + "A frozen area is created at the far end of the attack: enemies in it are frozen for {freeze}s and take a total of {patchBase} (+{patchPct}% Magic Power) magic damage over {patchDuration}s. "
                    + "Every 100 Magic Power adds \(Self.seconds(T.s2FreezePerHundredAP))s to the freeze.",
                tags: [KitTag.disrupt, KitTag.aoe])
        case .ultimate:
            return KitText(
                ja: "指定方向に霜の道を作り、道の上の敵に{pathBase}(+{pathPct}%魔法攻撃)の魔法ダメージを与えて、移動速度を{slowDuration}秒間{slow}%低下させる。"
                    + "霜の道はしだいに氷河となって最大まで広がったのち砕け、範囲内のすべての敵に{shatterBase}(+{shatterPct}%魔法攻撃)の魔法ダメージを与えて{freeze}秒間凍結させる。"
                    + "魔法攻撃100ごとに凍結時間が\(Self.seconds(T.ultFreezePerHundredAP))秒延びる。",
                en: "Create a frost path in the target direction, dealing {pathBase} (+{pathPct}% Magic Power) magic damage to enemies in the path and reducing their Movement Speed by {slow}% for {slowDuration}s. "
                    + "The frost path gradually becomes glaciers that spread to their maximum size and shatter, dealing {shatterBase} (+{shatterPct}% Magic Power) magic damage to all enemies in the area and freezing them for {freeze}s. "
                    + "Every 100 Magic Power adds \(Self.seconds(T.ultFreezePerHundredAP))s to the freeze.",
                tags: [KitTag.disrupt, KitTag.aoe])
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

    /// S1: 氷の隕石（0.56 秒後に着弾、鈍足）→ 0.47 秒後から 0.15 秒おきに雹 5 発（隕石と同じ円の敵全員に当たる）。
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

        // 雹: 隕石と同じ円の持続ゾーン 1 つ。発動 + 0.15 秒おきの 4 回 = 5 発（雹は減速を掛け直さない）
        let hailPayload = HitPayload(damage: hail, damageType: c.numbers.damageType, source: .skill(.skill1),
                                     skillID: skillID)
        ZoneSystem.spawn(&s, ownerIndex: i, center: center, radius: T.s1Radius, delay: T.s1Delay + T.hailGap,
                         duration: T.hailInterval * Double(T.s1Hails - 1), tickInterval: T.hailInterval,
                         payload: hailPayload, visual: Self.passiveVisual(ctx))
    }

    /// S2: 霜風（0.56 秒後に扇状に当たる。ダメージだけ）と、扇の先の半分の凍結エリア（0.76 秒後にでき、その瞬間に
    /// エリア内の敵を凍結し、0.13 秒おきに合計ダメージを 3 回に分けて与える）。
    private func castBreeze(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        let skillID = c.check.skill.skillID
        s.units[i].hero!.kit!.oriaAreaFreeze = Self.breezeFreeze(abilityPower: s.units[i].stats.abilityPower)
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * T.s2Range, shape: .fan, halfAngle: T.s2HalfAngle,
                     duration: T.s2Delay, count: 1)

        let wave = HitPayload(damage: c.numbers.damage, damageType: c.numbers.damageType, source: .skill(.skill2),
                              skillID: skillID)
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin, radius: T.s2Range,
                         shape: .cone(direction: dir, halfAngle: T.s2HalfAngle), delay: T.s2Delay, payload: wave,
                         visual: c.check.skill.effectID)

        // 凍結エリア = 同じ扇の、術者から s2AreaInner より先（innerRadius）。
        // kitEvent: 凍結エリアの凍結（onHit。最初の適用だけ）。kitHitsStructures: エリアの凍結はタワーにも効く（freezeTurret）
        let tick = Self.patchTotal(rank: c.numbers.rank, stats: s.units[i].stats) / Double(T.s2PatchTicks)
        let patch = HitPayload(damage: tick, damageType: c.numbers.damageType, source: .skill(.skill2), skillID: skillID,
                               kitEvent: T.Event.frozenArea, kitHitsStructures: true)
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin, radius: T.s2Range,
                         shape: .cone(direction: dir, halfAngle: T.s2HalfAngle), delay: T.s2AreaDelay,
                         duration: T.s2PatchDuration, tickInterval: T.s2PatchInterval, innerRadius: T.s2AreaInner,
                         payload: patch, visual: c.check.skill.effectID)
    }

    /// 奥義: 霜の道（0.26 秒後に、撃った位置・向きの細い帯の敵へ一度に当たる。鈍足）と、道に沿った帯の氷河
    /// （1.49 秒後に砕け、範囲の敵を凍結）。
    private func castGlacier(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        let origin = s.units[i].pos
        let dir = c.aim.direction
        let skillID = c.check.skill.skillID
        let visual = c.check.skill.effectID
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * T.ultRange, shape: .wideLine,
                     duration: T.ultGlacierDelay, count: 1)

        // 霜の道: 撃った時点の段・魔力のダメージを持ち、撃った位置と向き（param = 角度）で当てる。スタンでは取り消さない
        // （隕石・霜風・氷河のゾーンと同じく、撃った後は止まらない。術者が倒れるとタイマーは消える）
        s.units[i].hero!.kit!.oriaPathDamage = c.numbers.damage
        Kit.schedule(&s, caster: i, slot: .ultimate, code: T.Code.path, after: T.ultPathDelay, param: dir.angle,
                     point: origin, interruptible: false)

        // 凍結の長さは発動時の魔力で決める（砕けるまでに魔力が変わっても、撃った時点の値）
        let freeze = StatusEffect(kind: .stun, duration: Self.glacierFreeze(abilityPower: s.units[i].stats.abilityPower),
                                  sourceID: id, tag: T.freezeTag)
        s.units[i].hero!.kit!.oriaGlacierFreeze = freeze.duration
        // kitHitsStructures: 砕けの凍結はタワーにも効く（freezeTurret）
        let shatter = HitPayload(damage: Self.shatterDamage(rank: c.numbers.rank, stats: s.units[i].stats),
                                 damageType: c.numbers.damageType,
                                 source: .skill(.ultimate), statuses: [freeze], skillID: skillID,
                                 kitEvent: T.Event.shatter, kitHitsStructures: true)
        // 氷河 = 術者の ultBack 後ろから前へ ultGlacierLength までの長方形（端の四角い線分のゾーン）。ゾーンの中心は前の端に置き、
        // 後ろ向きに伸ばす（演出の向き = 術者 → ゾーンの中心が前を向く）
        ZoneSystem.spawn(&s, ownerIndex: i, center: origin + dir * T.ultGlacierLength, radius: T.ultGlacierHalfWidth,
                         shape: .line(direction: dir * -1, length: T.ultGlacierLength + T.ultBack),
                         delay: T.ultGlacierDelay, squareEnds: true, payload: shatter, visual: visual)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard timer.code == T.Code.path, let k = s.units[owner].hero?.kit else { return }
        let id = s.units[owner].id
        let p = Self.pathPayload(damage: k.oriaPathDamage, sourceID: id,
                                 skillID: ctx.master.skill(hero: heroID, slot: .ultimate)?.skillID)
        let dir = Vec2.fromAngle(timer.param)
        let team = s.units[owner].team
        // 検証用の観測: 霜の道の長方形（pathTargets と同じ寸法。受け口が無ければ何もしない。docs/vfx/RANGES.md）
        HitShapeProbe.emit(.kit(.line(from: timer.point - dir * T.ultBack, to: timer.point + dir * T.ultRange,
                                      halfWidth: T.ultPathWidth, squareEnds: true), s, caster: owner,
                                source: .skill(.ultimate)))
        for j in Self.pathTargets(s, team: team, origin: timer.point, direction: dir) {
            CombatSystem.applyHit(&s, ctx, sourceID: id, team: team, targetIndex: j, payload: p, from: timer.point)
        }
    }

    /// 霜の道の命中: 公式の表の魔法ダメージ + 80% の減速 1.2 秒（`slow`、他の減速と最大値で重なる）。
    static func pathPayload(damage: Double, sourceID: EntityID, skillID: String?) -> HitPayload {
        let slow = StatusEffect(kind: .slow, duration: T.ultPathSlowDuration, magnitude: T.ultPathSlow, sourceID: sourceID,
                                tag: T.pathSlowTag)
        return HitPayload(damage: damage, damageType: .magic, source: .skill(.ultimate), statuses: [slow], skillID: skillID)
    }

    /// 霜の道が当たる敵（構造物・死亡を除く。添字昇順）: origin の ultBack 後ろから direction へ ultRange まで、半幅 ultPathWidth の
    /// 長方形（どの辺も対象の半径まで含む）。
    static func pathTargets(_ s: SimState, team: Team, origin: Vec2, direction: Vec2) -> [Int] {
        let dir = direction.normalized
        guard dir != .zero else { return [] }
        var out: [Int] = []
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            let r = s.units[j].radius
            let rel = s.units[j].pos - origin
            let along = rel.dot(dir)
            guard along >= -T.ultBack - r, along <= T.ultRange + r,
                  abs(rel.x * dir.y - rel.y * dir.x) <= T.ultPathWidth + r else { continue }
            out.append(j)
        }
        return out
    }

    /// 凍結エリアの命中: エリアができた瞬間（最初の適用）にエリア内にいる敵だけを凍結する
    /// （1 秒 + 魔法攻撃 100 ごとに 0.06 秒。撃った時点の魔力）。以降の適用はダメージだけ（凍結を掛け直さない）。
    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard s.units.indices.contains(target) else { return }
        if s.units[target].isStructure {
            freezeTurret(&s, ctx, owner: owner, target: target, event: event)
            return
        }
        guard event == T.Event.frozenArea, let k = s.units[owner].hero?.kit, CombatSystem.isLiving(s, target),
              Self.frozenAreaJustFormed(s, owner: owner, target: target) else { return }
        let duration = k.oriaAreaFreeze > 0 ? k.oriaAreaFreeze : T.s2Freeze
        let before = s.units[target].statuses.first { $0.kind == .stun && $0.tag == T.freezeTag }?.remaining ?? 0
        CombatSystem.addStatus(&s, targetIndex: target,
                               StatusEffect(kind: .stun, duration: duration, sourceID: s.units[owner].id,
                                            tag: T.freezeTag))
        let after = s.units[target].statuses.first { $0.kind == .stun && $0.tag == T.freezeTag }?.remaining ?? 0
        if after > before + 1e-9 {
            s.emit(.ccApplied(targetID: s.units[target].id, cc: .stun, duration: duration))
        }
    }

    /// オーリアの凍結はタワーにも効く（公式「自身のフリーズ効果はタワーにも適用」）。凍結エリア（できた瞬間のエリア内）と
    /// 氷河の砕けの範囲の敵の構造物（ZoneSystem が HitPayload.kitHitsStructures で呼ぶ）を、ヒーローと同じ秒数だけ凍らせる。
    /// 構造物へのダメージは無い（公式の記載なし）。無敵の構造物は凍らない（Kit.freezeStructure）。
    private func freezeTurret(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        let duration: Double
        switch event {
        case T.Event.frozenArea:
            guard Self.frozenAreaJustFormed(s, owner: owner, target: target) else { return }
            duration = k.oriaAreaFreeze > 0 ? k.oriaAreaFreeze : T.s2Freeze
        case T.Event.shatter:
            duration = k.oriaGlacierFreeze > 0 ? k.oriaGlacierFreeze : T.ultFreeze
        default:
            return
        }
        Kit.freezeStructure(&s, ctx, target: target, duration: duration, sourceID: s.units[owner].id, tag: T.freezeTag)
    }

    /// 対象 target を含むオーリアの凍結エリアが、今できたところ（ゾーンの最初の適用）か。
    /// ZoneSystem は発動した tick には持続（duration）を減らさないので、最初の適用のときだけ残りが s2PatchDuration のまま。
    /// 対象がそのエリアに入っていることも見る（練習場で CD なしに重ねたとき、別のエリアの最初の適用で凍らせないため）。
    static func frozenAreaJustFormed(_ s: SimState, owner: Int, target: Int) -> Bool {
        let ownerID = s.units[owner].id
        let pos = s.units[target].pos
        let r = s.units[target].radius
        return s.zones.contains { z in
            z.ownerID == ownerID && z.triggered && !z.done && z.payload.kitEvent == T.Event.frozenArea
                && z.duration > T.s2PatchDuration - Balance.dt / 2
                && ZoneSystem.contains(zone: z, point: pos, pointRadius: r)
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
        // 氷の誇りの再発動までの残りと、遅れて働く凍結エリア・氷河の凍結秒は、死亡しても残る
        fresh.oriaPrideCooldown = old.oriaPrideCooldown
        fresh.oriaAreaFreeze = old.oriaAreaFreeze
        fresh.oriaGlacierFreeze = old.oriaGlacierFreeze
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

    /// 致命傷を無効にして凍りつく: HP 1・シールドは失う・行動不能（suppress）+ 無敵・最大 HP の 30% を 1.5 秒かけて回復（全レベル一定）。
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
        s.units[i].hero!.kit!.oriaHealPerTick = s.units[i].stats.maxHP * T.prideHealRatio / Double(ticks)
        s.units[i].hero!.kit!.oriaPrideCooldown = noCooldowns ? 0 : T.prideCooldown
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let dist = s.units[bot].pos.distance(to: s.units[target].pos)
        switch slot {
        case .skill2:
            // 凍結は扇の先の半分の凍結エリアでだけ: 相手がエリアに入る距離（術者から s2AreaInner〜s2Range）のときだけ撃つ
            // （扇の手前の敵はダメージだけになる）
            guard dist >= T.s2AreaInner, dist <= T.s2Range else { return .skip }
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

    // 説明文の extras は整数に丸めて見せるので、実際のダメージは段と能力値から丸めずに求める（公式の式: 基礎[段] + 係数 × 魔法攻撃）。

    /// S1: 氷の隕石（400 / 460 / 520 / 580 / 640 / 700 + 90% 魔法攻撃）。
    static func meteorDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(T.s1MeteorBase, rank: rank, ratio: T.s1MeteorPowerRatio, .magicPower, stats: stats)
    }

    /// S1: 雹 1 発（40 + 10% 魔法攻撃。全 Lv 一定）。
    static func hailDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(T.s1HailBase, rank: rank, ratio: T.s1HailPowerRatio, .magicPower, stats: stats)
    }

    /// S2: 霜風（225 / 255 / 285 / 315 / 345 / 375 + 75% 魔法攻撃）。
    static func breezeDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(T.s2HitBase, rank: rank, ratio: T.s2HitPowerRatio, .magicPower, stats: stats)
    }

    /// S2: 凍結エリアの合計（225 → 375 + 75% 魔法攻撃）。
    static func patchTotal(rank: Int, stats: Stats) -> Double {
        Kit.official(T.s2PatchBase, rank: rank, ratio: T.s2PatchPowerRatio, .magicPower, stats: stats)
    }

    /// 奥義: 霜の道（100 / 150 / 200 + 40% 魔法攻撃）。
    static func pathDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(T.ultPathBase, rank: rank, ratio: T.ultPathPowerRatio, .magicPower, stats: stats)
    }

    /// 奥義: 氷河が砕けるダメージ（600 / 900 / 1200 + 150% 魔法攻撃）。
    static func shatterDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(T.ultShatterBase, rank: rank, ratio: T.ultShatterPowerRatio, .magicPower, stats: stats)
    }

    /// 説明文に埋める秒数（0.06 のような小数 2 桁も落とさない）。
    static func seconds(_ v: Double) -> String { String(format: "%g", v) }

    /// 雹・補助のゾーンに使う演出 ID（パッシブの演出 ID。隕石・霜風・奥義の演出と重ねないため）。
    static func passiveVisual(_ ctx: SimContext) -> String {
        ctx.master.skill(hero: "H031", slot: .passive)?.effectID ?? ""
    }
}

extension Kit_H031 {
    /// ZoneSystem.spawn と同じ形（描画の事前生成用。HeroKit.plannedZones）。
    func plannedZones(master: MasterData) -> [KitZoneShape] {
        // S1 隕石 + 雹（同じ円の 2 つ）、S2 霜風の扇 + 凍結エリア（同じ扇の 2 つ）、奥義の氷河（帯 = 線のゾーン。線のメッシュは
        // 共有なので、ここは見た目のプールの数の見積りに効く）
        [KitZoneShape(radius: T.s1Radius, count: 2), KitZoneShape(radius: T.s2Range, halfAngle: T.s2HalfAngle, count: 2),
         KitZoneShape(radius: T.ultGlacierHalfWidth)]
    }
}
