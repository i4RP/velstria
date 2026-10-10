import Foundation

// 担当: kit-H032（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Dyrroth.md）
// H032 赤拳のディアス = Velstria 版の Dyrroth（MLBB。調査: docs/kits/Dyrroth.md、対応表: 同ファイル末尾）。
// デュエリスト（EXP）の近接。キットはロールの汎用パッシブ（通常攻撃の攻撃速度スタック）を置き換える。
//   パッシブ 紅血の拳（Wrath of the Abyss）— レイジ（0〜100）が時間でたまる（毎秒 2〜5%、レベルで増える。MLBB と同じ）。
//                           50 以上でスキル1・スキル2 が「アビス強化」になり、使うと 50 を消費する。
//                           HUD のバッジ = Int(レイジ / 50)（0〜2）。演出（SkillFXDirector）はバッジが増えた瞬間（50・100）だけ出す
//                           通常攻撃 2 回に 1 回は円撃（Circle Strike）: 周囲の敵へ攻撃力の 150〜180%（タワーには乗らない）、最大 HP の 1.4〜2% 回復（公式 7〜10% の 0.2 倍）
//                           （ミニオン・タワーだけが相手なら半分）。敵ヒーローにダメージを与えるたび S1・S2 の CD が縮む。
//   S1   赤拳連斬（Burst Strike）— 前方の扇へ 3 連（アビス強化は 5 連）の衝撃。1 発目 240 → 520（+60% 物理攻撃）、2 発目以降は 30%、ミニオンへは 75%。
//                           鈍足 25%（アビス強化 50%）1.5 秒。アビス強化は射程が伸び、1 発ごとに 140%（1 発目 140%・以降 42%）。
//   S2   紅蓮の踏込（Spectre Step）— 1 回目: 指定方向へ突進し、最初に当たった敵（ヒーロー・ミニオン・モンスター）で止まって
//                           ダメージ + 軽く押し出す。3 秒以内の再使用（同じ castSkill）で 2 回目の致命の一撃:
//                           敵ヒーローへ飛びかかり、ダメージ + 物理防御 −40%（アビス強化 −60% + 鈍足 90% 1 秒、射程と威力 150%）4 秒。
//                           ダメージは 230 → 355（+60% 追加物理攻撃）/ 345 → 570（+120% 追加物理攻撃）。
//   奥義 奈落の一撃（Abysm Strike）— 0.5 秒の溜め（その場から動けない。CC では止まらず、suppress だけで中断）のあと、
//                           前方 650 の直線上（半幅 140）の敵へ 650 / 950 / 1250（+250% 追加物理攻撃）+ 対象の失った HP の 20% + 鈍足 55% 0.8 秒
//                           （ヒーロー以外へは合計に上限 1500 / 2000 / 2500 を換算した値）。
//                           ボットは溜めの間の敵の動きを読んで撃つ（botCast。敵ヒーローに届けば汎用の関門を待たない）。
// 数値の正は公式（現行シーズン。docs/kits/Dyrroth.md の「公式（現行シーズン）の数値」）。ダメージは公式の表をランクへ線形補間し、
//   (基礎 + 係数 × 攻撃力 × skillAttackScalingFactor) × スロット倍率 × 換算（Tune.burstScale / spectreScale / ultScale）。H029 ボルグと同じ方法。
//   「追加物理攻撃」の係数は Unit.baseStats との差（装備・バフで増えた分）に掛ける。コストは公式どおり無し（HeroKit.cost = 0）。
//
// 状態（KitState）:
//   reals[0] = レイジ（0..100）       reals[1] = 突進（S2 の 1・2 回目）の命中ダメージ   reals[2..3] = 奥義の向き
//   reals[4] = 奥義の基礎ダメージ（発動時に確定）   reals[5] = 奥義のヒーロー以外へのダメージの上限（発動時に確定）
//   ints[0]  = 通常攻撃の数（円撃までの数え）   ints[1] = 発動の通し番号   ints[2] = CD 短縮を渡した通し番号
//   ints[3]  = 突進がアビス強化か（1 = 強化。割り込みで返却する）   ints[4] = 奥義の溜め中（0/1）
//   ints[5]  = アビス強化の累計回数（検証用）   ints[6] = 円撃の累計回数（検証用）
//   timers[0] = 奥義の溜めの残り秒（HUD 用）   ids[0] = 突進の対象

extension KitState {
    var diasRage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }

    var diasDashDamage: Double {
        get { reals[1] }
        set { reals[1] = newValue }
    }

    var diasUltDirection: Vec2 {
        get { Vec2(reals[2], reals[3]) }
        set {
            reals[2] = newValue.x
            reals[3] = newValue.y
        }
    }

    var diasUltDamage: Double {
        get { reals[4] }
        set { reals[4] = newValue }
    }

    /// 奥義のヒーロー以外へのダメージの上限（発動時のランクで確定）。
    var diasUltCap: Double {
        get { reals[5] }
        set { reals[5] = newValue }
    }

    var diasSwings: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var diasCastSerial: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var diasRefundedSerial: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var diasDashAbyss: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var diasUltCharging: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    var diasAbyssUses: Int {
        get { ints[5] }
        set { ints[5] = newValue }
    }

    var diasCircles: Int {
        get { ints[6] }
        set { ints[6] = newValue }
    }

    var diasUltCharge: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var diasDashTargetID: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }
}

struct Kit_H032: HeroKit {
    let heroID = "H032"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H032(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100 を近接スキルの射程に合わせて調整）

    enum Tune {
        // パッシブ: レイジ
        static let rageMax = 100.0
        /// 毎秒のレイジ（MLBB と同じ 2〜5%/s をレベル 1〜最大で補間）。以前は CD が半分だったので ×2 していた（CD 1 回あたりのレイジは同じ）。
        static let rageGain = (2.0, 5.0)
        /// アビス強化に要るレイジと、使ったときの消費量（公式: 50% で強化。消費量は Fandom の注記の 50）。
        static let abyssCost = 50.0

        // パッシブ: 円撃（Circle Strike）
        static let circleEvery = 2
        static let circleRatio = (1.5, 1.8)
        /// 公式は最大 HP の 7〜10%（レベルで増える）。Velstria の TTK は MLBB よりずっと短い（2.5〜22 秒）ので、伸び方はそのまま 0.2 倍にした
        /// （1.4〜2%。以前は 3〜4%。公式の表へ置き換えてコストが 0 になったぶん Lv12 がデュエリスト中央値 +28 pt だった）。
        static let circleHeal = (0.014, 0.02)
        /// 円撃の半径（術者の中心から。対象の半径は別に足す）。通常攻撃の射程 150 より少し広い（MLBB 1.7 → 2.0 の比）。
        static let circleRadius = 190.0
        /// ミニオン・モンスター・タワーだけが相手のときの回復の倍率。
        static let circleHealNonHero = 0.5

        // パッシブ: 敵ヒーローにダメージを与えるたびに S1・S2 のクールダウンを縮める秒数。
        // 通常攻撃・円撃の命中 = cooldownRefund、スキルの命中（1 回の発動につき 1 度）= skillCooldownRefund。
        // 公式は 1 秒。そのままだとスキルの稼働率が上がりすぎて 1v1 の勝率が汎用の Duelist より上へ偏るので、通常攻撃・円撃は
        // 公式の 55%（0.55 秒）、スキルの命中は 5%（0.05 秒）に抑える（docs/kits/Dyrroth.md の「バランス」。以前は 0.6 / 0.1 秒）。
        // 0.3 秒まで下げると勝率は一番よく揃うが、旧式の台本の 1v1 で H028 に Lv6 で負けるようになり、H028 の総当たりの上限（85%）を超えた。
        static let cooldownRefund = 0.55
        static let skillCooldownRefund = 0.05

        // S1 爆裂連撃
        static let burstReach = 300.0
        static let burstReachAbyss = 400.0
        static let burstHalfAngle = 0.65
        static let burstCount = 3
        static let burstCountAbyss = 5
        static let burstFirstDelay = 0.1
        static let burstInterval = 0.14
        static let burstIntervalAbyss = 0.11
        /// 同じ敵への連続ヒットの減衰（1 発目に対する倍率。公式の Fandom の表: 通常 {100%, 30%, 30%}、強化 {140%, 42% × 4} = 強化の倍率 1.4 × これ）。
        static let burstDecay: [Double] = [1.0, 0.3, 0.3]
        static let burstDecayAbyss: [Double] = [1.0, 0.3, 0.3, 0.3, 0.3]
        /// ミニオンへのダメージ倍率（公式 75%）。
        static let burstMinionFactor = 0.75
        static let burstSlow = 0.25
        static let burstSlowAbyss = 0.50
        static let burstSlowDuration = 1.5
        static let burstSlowTag = KitTags.buff("H032", "burstSlow")
        /// 公式: 1 発ごとに 240 / 296 / 352 / 408 / 464 / 520（+60% 物理攻撃）。アビス強化は 1 発ごとに元のダメージの 140%。
        static let burstBase = (240.0, 520.0)
        static let burstAttackRatio = 0.6
        static let abyssBurstMultiplier = 1.4
        /// 公式の値 → Velstria の換算（sim の通常の式 × スロット倍率の後ろに掛ける）。
        /// 減衰（2 発目以降 30%）で通常版の単体合計は 1 発目の 1.6 倍、アビス強化は 1.4 × 2.2 = 3.08 倍（通常版の 1.925 倍）になる。
        /// 強化版は汎用 S1 の 0.79〜1.05 倍、通常版は 0.41〜0.54 倍（Lv12 の勝率で決めた値。docs/kits/Dyrroth.md の「バランス」）。
        static let burstScale = 0.18

        // S2 亡霊の歩み
        static let dashRange = 400.0
        /// 進路の当たり幅（半幅。対象の半径は別に足す）。
        static let dashWidth = 110.0
        static let dashSpeed = 2400.0
        /// 1 回目の命中で押し出す距離と時間（「わずかに押し出す」）。
        static let pushDistance = 130.0
        static let pushDuration = 0.18
        /// 突進中に対象が離れすぎたら外れる余裕（半径の和に足す）。
        static let dashSlack = 140.0
        static let fatalReach = 350.0
        static let fatalReachAbyss = 500.0
        static let fatalSpeed = 2600.0
        static let fatalSlack = 220.0
        static let recastWindow = 3.0
        /// 公式: 1 回目 230 / 255 / 280 / 305 / 330 / 355（+60% 追加物理攻撃）、2 回目（致命の一撃）345 / 390 / 435 / 480 / 525 / 570
        /// （+120% 追加物理攻撃）。追加物理攻撃 = 装備などで増えた分（物理攻撃 − レベルの基礎値。Unit.baseStats）。
        static let dashBase = (230.0, 355.0)
        static let dashExtraRatio = 0.6
        static let fatalBase = (345.0, 570.0)
        static let fatalExtraRatio = 1.2
        /// 公式の値 → Velstria の換算（1 回目と 2 回目で共通）。1 回目 + 2 回目が汎用 S2 の 0.8〜1.3 倍に収まる値。
        static let spectreScale = 0.33
        static let abyssFatalMultiplier = 1.5
        static let shred = 0.40
        static let shredAbyss = 0.60
        static let shredDuration = 4.0
        static let shredTag = KitTags.buff("H032", "shred")
        /// アビス強化の致命の一撃の追加の鈍足（公式 90%。秒数は Fandom の 1 秒）。
        static let fatalSlowAbyss = 0.9
        static let fatalSlowDuration = 1.0
        static let fatalSlowTag = KitTags.buff("H032", "fatalSlow")

        // 奥義 奈落の一撃
        /// 奥義の射程。0.5 秒の溜めで向きが固定されるので、MLBB の「画面の半分ほど届く長い直線」（約 7 m）に寄せて
        /// 420 → 650 に伸ばした（溜めの間に避けられても、見てから撃てる距離。ボットは敵の動きを読んで撃つ）。
        static let ultReach = 650.0
        /// 直線の幅（半幅）。
        static let ultHalfWidth = 140.0
        /// ボットが奥義を「今撃つ」現在の距離の上限（射程いっぱいは外れやすいので少し手前まで）と、動きを読む秒数の上限。
        static let ultBotReach = 540.0
        /// 直線の長さ（線分の部分）。命中は線分から半幅 + 対象の半径までなので、丸い端を含めて射程 650 ちょうどに収まる。
        static let ultLineLength = ultReach - ultHalfWidth
        static let ultCharge = 0.5
        /// 対象の失った HP の 20%（公式。Liquipedia・Fandom とも）。換算せずそのまま足す。
        static let ultLostHealth = 0.20
        static let ultSlow = 0.55
        static let ultSlowDuration = 0.8
        static let ultSlowTag = KitTags.buff("H032", "ultSlow")
        static let ultChannelTag = KitTags.buff("H032", "channel")
        /// 公式: 650 / 950 / 1250（+250% 追加物理攻撃）。ヒーロー以外へのダメージの上限 1500 / 2000 / 2500（基礎と同じ換算を掛ける）。
        static let ultBase = (650.0, 1250.0)
        static let ultExtraRatio = 2.5
        static let ultNonHeroCap = (1500.0, 2500.0)
        /// 公式の値 → Velstria の換算。基礎ダメージは汎用の奥義（Duelist = 3 連撃）の合計の 0.57〜0.80 倍（予算の下限 0.8 を割る）:
        /// 失った HP の 20% が換算なしで乗り、クールダウン短縮・円撃もあるので、Lv12 の勝率で決めた値。
        static let ultScale = 0.40

        // クールダウン（MLBB の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
        static let burstCooldown = (6.0, 4.0)
        static let spectreCooldown = (6.0, 6.0)
        static let ultCooldown = (36.0, 28.0)
        // コスト: 公式はどのスキルも無し（HeroKit.cost で 0。マスターの Energy の値は使わない）
    }

    /// KitTimer.code
    private enum Code {
        static let burst = 1
        static let burstAbyss = 2
        static let dashArrive = 3
        static let fatalArrive = 4
        static let ultRelease = 5
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 前方の扇（近接の cone）。アビス強化の射程の伸びは発動時に決まる（状態が要るので照準情報は通常の値）
            var t = base
            t.archetype = .cone
            t.aim = .direction
            t.range = Tune.burstReach
            t.radius = Tune.burstReach
            t.shape = .fan
            t.halfAngle = Tune.burstHalfAngle
            return t
        case .skill2:
            if stage >= 1 {
                // 致命の一撃: 敵ヒーローを指定して飛びかかる（ミニオン・モンスターは選べない）
                return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.fatalReach, radius: 150,
                                      shape: .lockOn, requiresTarget: true, recastable: true)
            }
            // 突進（最初に当たった敵で止まる）。radius は進路の当たり半幅
            return SkillTargeting(archetype: .dashStrike, aim: .direction, range: Tune.dashRange,
                                  radius: Tune.dashWidth, shape: .dashToPoint, recastable: true)
        case .ultimate:
            // 溜めのあとの直線（射程 650）。radius は線の半幅
            return SkillTargeting(archetype: .piercingLine, aim: .direction, range: Tune.ultReach,
                                  radius: Tune.ultHalfWidth, shape: .wideLine)
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
            n.extras = [KitStat(key: "rageMin", value: Tune.rageGain.0),
                        KitStat(key: "rageMax", value: Tune.rageGain.1),
                        KitStat(key: "circleMin", value: Tune.circleRatio.0 * 100),
                        KitStat(key: "circleMax", value: Tune.circleRatio.1 * 100)]
        case .skill1:
            // damage = 単体に 3 発とも当たったときの 1 発あたりの平均（totalDamage = 単体の合計 = 1 発目 × 1.6）
            let first = Self.burstDamage(rank: rank, stats: stats)
            let total = first * Tune.burstDecay.reduce(0, +)
            let abyssTotal = first * Tune.abyssBurstMultiplier * Tune.burstDecayAbyss.reduce(0, +)
            n.hits = Tune.burstCount
            n.damage = total / Double(Tune.burstCount)
            n.cooldown = Self.cooldown(Tune.burstCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccDuration = Tune.burstSlowDuration
            n.extras = [KitStat(key: "abyssHits", value: Double(Tune.burstCountAbyss)),
                        KitStat(key: "abyssTotal", value: abyssTotal),
                        KitStat(key: "slow", value: Tune.burstSlow * 100),
                        KitStat(key: "abyssSlow", value: Tune.burstSlowAbyss * 100),
                        KitStat(key: "first", value: first.rounded()),
                        KitStat(key: "base", value: Self.scaledBase(Tune.burstBase, slot: .skill1, scale: Tune.burstScale,
                                                                    rank: rank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.burstAttackRatio, slot: .skill1,
                                                                         scale: Tune.burstScale).rounded()),
                        KitStat(key: "decay", value: Tune.burstDecay[1] * 100),
                        KitStat(key: "minion", value: Tune.burstMinionFactor * 100),
                        KitStat(key: "abyssPct", value: Tune.abyssBurstMultiplier * 100),
                        KitStat(key: "slowDuration", value: Tune.burstSlowDuration),
                        KitStat(key: "abyssShown", value: abyssTotal.rounded())]
        case .skill2:
            // 追加物理攻撃の分は発動時に足す（numbers の能力値からは基礎値が分からないため。HUD の値は装備なしの値）
            let dash = Self.scaledBase(Tune.dashBase, slot: .skill2, scale: Tune.spectreScale, rank: rank)
            let fatal = Self.scaledBase(Tune.fatalBase, slot: .skill2, scale: Tune.spectreScale, rank: rank)
            n.hits = 1
            n.damage = stage >= 1 ? fatal : dash
            n.cc = stage >= 1 ? .none : .knockback
            n.ccDuration = stage >= 1 ? 0 : Tune.pushDuration
            n.cooldown = Self.cooldown(Tune.spectreCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.stages = 2
            n.recastWindow = Tune.recastWindow
            n.extras = [KitStat(key: "fatalDamage", value: fatal),
                        KitStat(key: "shred", value: Tune.shred * 100),
                        KitStat(key: "abyssFatalDamage", value: fatal * Tune.abyssFatalMultiplier),
                        KitStat(key: "abyssShred", value: Tune.shredAbyss * 100),
                        KitStat(key: "dashBase", value: dash.rounded()),
                        KitStat(key: "dashPct", value: Self.attackPercent(Tune.dashExtraRatio, slot: .skill2,
                                                                          scale: Tune.spectreScale).rounded()),
                        KitStat(key: "fatalBase", value: fatal.rounded()),
                        KitStat(key: "fatalPct", value: Self.attackPercent(Tune.fatalExtraRatio, slot: .skill2,
                                                                           scale: Tune.spectreScale).rounded()),
                        KitStat(key: "abyssPct", value: Tune.abyssFatalMultiplier * 100),
                        KitStat(key: "abyssSlow", value: Tune.fatalSlowAbyss * 100),
                        KitStat(key: "abyssSlowDuration", value: Tune.fatalSlowDuration),
                        KitStat(key: "shredDuration", value: Tune.shredDuration),
                        KitStat(key: "window", value: Tune.recastWindow)]
        case .ultimate:
            n.hits = 1
            n.damage = Self.ultDamage(rank: rank)
            n.cc = .slow
            n.ccIsUltimate = false
            n.ccDuration = Tune.ultSlowDuration
            // 汎用の連撃の被ダメ軽減は持たない
            n.damageReduction = 0
            n.damageReductionDuration = 0
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "lostHealth", value: Tune.ultLostHealth * 100),
                        KitStat(key: "charge", value: Tune.ultCharge),
                        KitStat(key: "slow", value: Tune.ultSlow * 100),
                        KitStat(key: "slowDuration", value: Tune.ultSlowDuration),
                        KitStat(key: "base", value: n.damage.rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.ultExtraRatio, slot: .ultimate,
                                                                         scale: Tune.ultScale).rounded()),
                        KitStat(key: "cap", value: Self.ultNonHeroCap(rank: rank).rounded())]
        }
        return n
    }

    /// コストは公式どおり無し（どのスキルも 0。マスターの Energy の値は使わない）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        slot == .passive ? base : 0
    }

    func text(slot: SkillSlot) -> KitText? {
        let heal = "\(String(format: "%g", Tune.circleHeal.0 * 100))〜\(String(format: "%g", Tune.circleHeal.1 * 100))"
        let abyss = Int(Tune.abyssCost)
        switch slot {
        case .passive:
            let hit = String(format: "%g", Tune.cooldownRefund)
            let skillHit = String(format: "%g", Tune.skillCooldownRefund)
            return KitText(
                ja: "レイジが\(abyss)%に達すると、スキル1とスキル2を強化する（アビス強化。使うとレイジを\(abyss)消費する）。"
                    + "\n\n通常攻撃\(Tune.circleEvery)回ごとに円撃を放ち、円の中の敵に物理攻撃の{x2}% 〜 {x3}%（レベルで増える）の物理ダメージを与え（強化ダメージはタワーには乗らない）、"
                    + "最大HPの\(heal)%（レベルで増える。ミニオン・タワーだけが相手なら半分）を回復する。"
                    + "\n\n敵ヒーローに通常攻撃（円撃を含む）でダメージを与えるたびにスキル1とスキル2のクールダウンが\(hit)秒、スキルで与えるたび（1回の発動につき1度）に\(skillHit)秒短縮される。"
                    + "\n\nレイジは毎秒{x0}% 〜 {x1}%（レベルで増える）回復する。",
                en: "When Rage reaches \(abyss)%, Skill 1 and Skill 2 become Abyss Enhanced (using one spends \(abyss) Rage). "
                    + "\n\nAfter every \(Tune.circleEvery) basic attacks, release a Circle Strike, dealing {x2}% - {x3}% (scales with level) of Physical Attack as physical damage to enemies in the circle (the enhanced damage does not apply to turrets) "
                    + "and recovering \(heal)% Max HP (scales with level; halved against only minions or turrets). "
                    + "\n\nEach time a basic attack (including a Circle Strike) damages an enemy hero, the cooldowns of Skill 1 and Skill 2 are reduced by \(hit)s; each time a skill does (once per cast), by \(skillHit)s. "
                    + "\n\nRage recovers by {x0}% - {x1}% per second (scales with level).",
                tags: [KitTag.buff, KitTag.heal])
        case .skill1:
            return KitText(
                ja: "指定方向に衝撃を{hits}回放ち、1回ごとに{base}(+{atkPct}%物理攻撃)の物理ダメージを与えて、移動速度を{slowDuration}秒間{slow}%低下させる"
                    + "（同じ敵への2回目以降のダメージは{decay}%に減衰し、ミニオンには{minion}%。単体への合計{total}）。"
                    + "\n\nアビス強化：射程が伸び（\(Int(Tune.burstReachAbyss))）、{abyssHits}回放つ。1回ごとのダメージは元の{abyssPct}%（単体への合計{abyssShown}）、減速効果は2倍の{abyssSlow}%。",
                en: "Release {hits} bursts in the designated direction, each dealing {base} (+{atkPct}% Physical Attack) physical damage and slowing enemies by {slow}% for {slowDuration}s "
                    + "(repeat hits on the same target deal {decay}% and minions take {minion}%; {total} in total to one target). "
                    + "\n\nAbyss Enhanced: longer range (\(Int(Tune.burstReachAbyss))) and {abyssHits} bursts, each dealing {abyssPct}% of the original damage ({abyssShown} in total to one target), with the slow doubled to {abyssSlow}%.",
                tags: [KitTag.aoe, KitTag.slow])
        case .skill2:
            return KitText(
                ja: "指定方向へ突進し、最大距離に達するか敵（ヒーロー・ミニオン・モンスター）に当たると止まり、その敵に{dashBase}(+{dashPct}%追加物理攻撃)の物理ダメージを与えてわずかにノックバックさせる。"
                    + "\n\n再発動：{window}秒以内にもう一度使うと、敵ヒーローをロックオンして致命の一撃を放ち、{fatalBase}(+{fatalPct}%追加物理攻撃)の物理ダメージを与えて、物理防御を{shredDuration}秒間{shred}%低下させる。"
                    + "\n\nアビス強化：致命の一撃の射程が伸び（\(Int(Tune.fatalReachAbyss))）、元のダメージの{abyssPct}%を与え、さらに{abyssSlowDuration}秒間{abyssSlow}%減速させて、物理防御を{shredDuration}秒間{abyssShred}%低下させる。",
                en: "Dash in the designated direction, stopping at max distance or when hitting an enemy (hero, minion or monster), dealing {dashBase} (+{dashPct}% Extra Physical Attack) physical damage to it and slightly knocking it back. "
                    + "\n\nRecast: use it again within {window}s to lock onto an enemy hero and release a Fatal Strike, dealing {fatalBase} (+{fatalPct}% Extra Physical Attack) physical damage and reducing its Physical Defense by {shred}% for {shredDuration}s. "
                    + "\n\nAbyss Enhanced: the Fatal Strike reaches further (\(Int(Tune.fatalReachAbyss))), deals {abyssPct}% of the original damage, slows the target by an extra {abyssSlow}% for {abyssSlowDuration}s and reduces its Physical Defense by {abyssShred}% for {shredDuration}s.",
                tags: [KitTag.mobility, KitTag.burst])
        case .ultimate:
            return KitText(
                ja: "{charge}秒の溜めのあと、指定方向（{range}）へ破壊の一撃を放つ（溜めの間はその場から動けず、制圧によってのみ中断される）。"
                    + "直線上の敵に{base}(+{atkPct}%追加物理攻撃)＋対象の失ったHPの{lostHealth}%の物理ダメージを与え、移動速度を{slowDuration}秒間{slow}%低下させる。"
                    + "ヒーロー以外へのダメージは最大{cap}。",
                en: "After a {charge}s delay (rooted in place; only suppression interrupts it), launch a destructive strike in the target direction ({range}), "
                    + "dealing {base} (+{atkPct}% Extra Physical Attack) plus {lostHealth}% of the target's lost HP as physical damage to enemies in its path and slowing them by {slow}% for {slowDuration}s. "
                    + "Deals up to {cap} damage to non-hero enemies.",
                tags: [KitTag.burst, KitTag.slow])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 50 ごとに 1 段（0〜2）。演出（SkillFXDirector）はバッジの数が増えた瞬間にだけパッシブの合図を出すので、
            // 毎秒増えるレイジそのものではなく閾値（50・100）を数える。レイジの細かい量は持たない
            let steps = Int(Tune.rageMax / Tune.abyssCost)
            return KitBadge(kind: .stacks, value: min(steps, Int(k.diasRage / Tune.abyssCost + 1e-9)), maxValue: steps)
        case .skill1, .skill2:
            // アビス強化の準備ができている
            guard k.diasRage >= Tune.abyssCost else { return nil }
            return KitBadge(kind: .form, value: 1, maxValue: 1)
        case .ultimate:
            guard k.diasUltCharging != 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.diasUltCharge, total: Tune.ultCharge)
        }
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        guard slot == .skill2, stage >= 1 else { return nil }
        // 溜め中・ルート中は飛びかかれない
        if (s.units[caster].hero?.kit?.diasUltCharging ?? 0) != 0 || s.units[caster].has(.root) { return .some(nil) }
        let abyss = (s.units[caster].hero?.kit?.diasRage ?? 0) >= Tune.abyssCost
        let reach = abyss ? Tune.fatalReachAbyss : Tune.fatalReach
        guard let u = Self.pickHero(s, caster: caster, reach: reach, target: target) else { return .some(nil) }
        return .some(SkillAiming.aim(at: u, s, caster: caster, range: reach,
                                     facing: Vec2.fromAngle(s.units[caster].facing)))
    }

    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        // 奥義の溜め中は、ほかのスキルを始められない
        (s.units[caster].hero?.kit?.diasUltCharging ?? 0) == 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        s.units[c.caster].hero!.kit!.diasCastSerial += 1
        switch c.slot {
        case .skill1: castBurst(&s, c)
        case .skill2: castSpectre(&s, ctx, c)
        case .ultimate: castAbysm(&s, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 発動の向きに、前方の扇の衝撃を 3 回（アビス強化は 5 回）。強化はレイジ 50 を消費して射程と威力が伸びる。
    private func castBurst(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let abyss = Self.spendRage(&s, i)
        let count = abyss ? Tune.burstCountAbyss : Tune.burstCount
        let decay = abyss ? Tune.burstDecayAbyss : Tune.burstDecay
        let interval = abyss ? Tune.burstIntervalAbyss : Tune.burstInterval
        let reach = abyss ? Tune.burstReachAbyss : Tune.burstReach
        // 1 発目のダメージ（damage は単体に 3 発当たったときの平均なので、合計 ÷ 減衰の和）。2 発目以降は 30%。
        // アビス強化は 1 発ごとに 140%（= 1 発目 140%・以降 42%）
        let first = c.numbers.damage * Double(Tune.burstCount) / Tune.burstDecay.reduce(0, +)
            * (abyss ? Tune.abyssBurstMultiplier : 1)
        let origin = s.units[i].pos
        let dir = c.aim.direction
        var shown = c
        shown.targeting.range = reach
        Kit.emitCast(&s, shown, origin: origin, target: origin + dir * reach, unit: c.aim.unit, shape: .fan,
                     halfAngle: Tune.burstHalfAngle,
                     duration: Tune.burstFirstDelay + interval * Double(count - 1), count: count)
        for k in 0..<count {
            Kit.schedule(&s, caster: i, slot: .skill1, code: abyss ? Code.burstAbyss : Code.burst,
                         after: Tune.burstFirstDelay + interval * Double(k), index: k,
                         param: first * decay[k], point: dir, interruptible: true)
        }
    }

    /// S2 の 1 回目: 最初に当たった敵の手前まで（なければ最大距離まで）突進。到着した tick に 1 度だけ当てる。再使用の窓を開く。
    private func castSpectre(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let from = s.units[i].pos
        let dir = c.aim.direction
        let blocker = Kit.firstBlocker(s, caster: i, direction: dir, maxDistance: Tune.dashRange,
                                       width: Tune.dashWidth)
        let travel = blocker?.distance ?? Tune.dashRange
        s.units[i].hero!.kit!.diasDashTargetID = blocker.map { s.units[$0.index].id } ?? 0
        s.units[i].hero!.kit!.diasDashDamage = c.numbers.damage
            + Self.extraAttackDamage(s, i, ratio: Tune.dashExtraRatio, slot: .skill2, scale: Tune.spectreScale)
        s.units[i].hero!.kit!.diasDashAbyss = 0
        // 経路上の敵には当てない carrier（ハード CC の中断と着地の通知だけを使う）
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.skill2), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * travel,
                                       speed: Tune.dashSpeed, payload: carrier, radius: 0,
                                       arriveCode: Code.dashArrive)
        Kit.emitCast(&s, c, origin: from, target: landing, unit: blocker?.index,
                     shape: .dashToPoint, duration: from.distance(to: landing) / Tune.dashSpeed, count: 1)
        Kit.openRecast(&s, caster: i, slot: .skill2, duration: Tune.recastWindow, stage: 1, charges: 1)
    }

    /// S2 の 2 回目（致命の一撃）: 敵ヒーローへ飛びかかり、到着した tick にダメージ + 防御ダウン。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        guard c.slot == .skill2, let t = c.aim.unit else {
            Kit.closeRecast(&s, ctx, caster: c.caster, slot: c.slot)
            return
        }
        let i = c.caster
        s.units[i].hero!.kit!.diasCastSerial += 1
        let abyss = Self.spendRage(&s, i)
        let from = s.units[i].pos
        let toTarget = s.units[t].pos - from
        let dir = toTarget.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : toTarget.normalized
        let reach = abyss ? Tune.fatalReachAbyss : Tune.fatalReach
        let gap = s.units[i].radius + s.units[t].radius + 5
        let travel = min(reach, max(0, toTarget.length - gap))
        s.units[i].hero!.kit!.diasDashTargetID = s.units[t].id
        let fatal = c.numbers.damage
            + Self.extraAttackDamage(s, i, ratio: Tune.fatalExtraRatio, slot: .skill2, scale: Tune.spectreScale)
        s.units[i].hero!.kit!.diasDashDamage = fatal * (abyss ? Tune.abyssFatalMultiplier : 1)
        s.units[i].hero!.kit!.diasDashAbyss = abyss ? 1 : 0
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.skill2), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * travel,
                                       speed: Tune.fatalSpeed, payload: carrier, radius: 0,
                                       arriveCode: Code.fatalArrive)
        var shown = c
        shown.targeting.range = reach
        Kit.emitCast(&s, shown, origin: from, target: s.units[t].pos, unit: t, shape: .lockOn,
                     duration: from.distance(to: landing) / Tune.fatalSpeed, count: abyss ? 2 : 1)
        Kit.advanceRecast(&s, ctx, caster: i, slot: .skill2)
    }

    /// 奥義: 溜めに入る（その場から動けない）。向きは発動時に固定。CC では止まらず、suppress だけで中断される。
    private func castAbysm(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        let pos = s.units[i].pos
        let dir = c.aim.direction
        s.units[i].hero!.kit!.diasUltDirection = dir
        s.units[i].hero!.kit!.diasUltDamage = c.numbers.damage
            + Self.extraAttackDamage(s, i, ratio: Tune.ultExtraRatio, slot: .ultimate, scale: Tune.ultScale)
        s.units[i].hero!.kit!.diasUltCap = Self.ultNonHeroCap(rank: c.numbers.rank)
        s.units[i].hero!.kit!.diasUltCharging = 1
        s.units[i].hero!.kit!.diasUltCharge = Tune.ultCharge
        s.units[i].attackTargetID = nil
        s.units[i].windupRemaining = nil
        s.units[i].moveIntent = .none
        s.units[i].path.removeAll()
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .root, duration: Tune.ultCharge, sourceID: id,
                                                                 tag: Tune.ultChannelTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .channeling, duration: Tune.ultCharge,
                                                                 sourceID: id, tag: Tune.ultChannelTag))
        Kit.emitCast(&s, c, origin: pos, target: pos + dir * Tune.ultReach, unit: c.aim.unit, shape: .wideLine,
                     duration: Tune.ultCharge, count: 1)
        // 溜めはハード CC で取り消さない（interruptible: false）。suppress は update が取り消す
        Kit.schedule(&s, caster: i, slot: .ultimate, code: Code.ultRelease, after: Tune.ultCharge, interruptible: false)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        switch timer.code {
        case Code.burst, Code.burstAbyss: burst(&s, ctx, owner: owner, timer: timer)
        case Code.dashArrive: dashLanded(&s, ctx, owner: owner)
        case Code.fatalArrive: fatalLanded(&s, ctx, owner: owner)
        case Code.ultRelease: release(&s, ctx, owner: owner)
        default: break
        }
    }

    /// S1 の 1 発ぶん: 今の位置から固定の向きの扇へ。ミニオンは減衰、鈍足を付ける。
    private func burst(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        let abyss = timer.code == Code.burstAbyss
        let slow = StatusEffect(kind: .slow, duration: Tune.burstSlowDuration,
                                magnitude: abyss ? Tune.burstSlowAbyss : Tune.burstSlow, sourceID: s.units[owner].id,
                                tag: Tune.burstSlowTag)
        let skillID = Self.skillID(ctx, .skill1)
        let center = s.units[owner].pos
        Kit.hitAreaEach(&s, ctx, caster: owner, center: center, radius: abyss ? Tune.burstReachAbyss : Tune.burstReach,
                        shape: .cone(direction: timer.point, halfAngle: Tune.burstHalfAngle)) { st, j in
            let factor = st.units[j].kind == .minion ? Tune.burstMinionFactor : 1
            return HitPayload(damage: timer.param * factor, damageType: .physical, source: .skill(.skill1),
                              statuses: [slow], skillID: skillID)
        }
    }

    /// S2 の 1 回目の到着: 止まった先の敵（まだ近くに居れば）にダメージ + 押し出し。
    private func dashLanded(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let kit = s.units[owner].hero?.kit else { return }
        s.units[owner].hero!.kit!.diasDashTargetID = 0
        guard let t = Self.liveEnemy(s, owner, id: kit.diasDashTargetID),
              Self.isNear(s, owner, t, slack: Tune.dashSlack) else { return }
        var p = HitPayload(damage: kit.diasDashDamage, damageType: .physical, source: .skill(.skill2),
                           skillID: Self.skillID(ctx, .skill2),
                           effects: [.pushAway(distance: Tune.pushDistance, duration: Tune.pushDuration)])
        p.originPos = s.units[owner].pos
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
    }

    /// S2 の 2 回目の到着: 対象の敵ヒーローにダメージ + 防御ダウン（アビス強化は鈍足も）。
    private func fatalLanded(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let kit = s.units[owner].hero?.kit else { return }
        let abyss = kit.diasDashAbyss == 1
        s.units[owner].hero!.kit!.diasDashTargetID = 0
        s.units[owner].hero!.kit!.diasDashAbyss = 0
        guard let t = Self.liveEnemy(s, owner, id: kit.diasDashTargetID), s.units[t].kind == .hero,
              Self.isNear(s, owner, t, slack: Tune.fatalSlack) else { return }
        let id = s.units[owner].id
        var statuses = [StatusEffect(kind: .armorShred, duration: Tune.shredDuration,
                                     magnitude: abyss ? Tune.shredAbyss : Tune.shred, sourceID: id, tag: Tune.shredTag)]
        if abyss {
            statuses.append(StatusEffect(kind: .slow, duration: Tune.fatalSlowDuration, magnitude: Tune.fatalSlowAbyss,
                                         sourceID: id, tag: Tune.fatalSlowTag))
        }
        var p = HitPayload(damage: kit.diasDashDamage, damageType: .physical, source: .skill(.skill2),
                           statuses: statuses, skillID: Self.skillID(ctx, .skill2))
        p.originPos = s.units[owner].pos
        CombatSystem.applyHit(&s, ctx, sourceID: id, team: s.units[owner].team, targetIndex: t, payload: p,
                              from: s.units[owner].pos)
    }

    /// 奥義の解放: 今の位置から固定の向きの直線上の敵へ、基礎ダメージ + 失った HP の 20%。ヒーロー以外へは合計に上限
    /// （公式の 1500 / 2000 / 2500 を基礎と同じに換算）。suppress 中は不発。
    private func release(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let kit = s.units[owner].hero?.kit, kit.diasUltCharging == 1 else { return }
        Self.endCharge(&s, owner)
        guard !s.units[owner].has(.suppress) else { return }
        let id = s.units[owner].id
        let slow = StatusEffect(kind: .slow, duration: Tune.ultSlowDuration, magnitude: Tune.ultSlow, sourceID: id,
                                tag: Tune.ultSlowTag)
        let skillID = Self.skillID(ctx, .ultimate)
        let flat = kit.diasUltDamage
        let cap = kit.diasUltCap
        let center = s.units[owner].pos
        Kit.hitAreaEach(&s, ctx, caster: owner, center: center, radius: Tune.ultHalfWidth,
                        shape: .line(direction: kit.diasUltDirection, length: Tune.ultLineLength)) { st, j in
            let amount = Self.ultHitDamage(flat: flat, lostHealth: Self.lostHealth(st.units[j]),
                                           isHero: st.units[j].kind == .hero, cap: cap)
            var p = HitPayload(damage: amount, damageType: .physical, source: .skill(.ultimate),
                               statuses: [slow], skillID: skillID)
            p.originPos = center
            return p
        }
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        // レイジは時間でたまる
        if k.diasRage < Tune.rageMax {
            let level = s.units[owner].hero?.level ?? 1
            let rate = Self.rageRate(level: level)
            s.units[owner].hero!.kit!.diasRage = min(Tune.rageMax, k.diasRage + rate * Balance.dt)
        }
        guard k.diasUltCharging != 0 else { return }
        // 溜め: suppress だけが中断する（ハード CC では取り消されない）
        if s.units[owner].has(.suppress) {
            Kit.cancelScheduled(&s, caster: owner, slot: .ultimate)
            Self.endCharge(&s, owner)
            return
        }
        // 溜めの間は動かず、攻撃も始めない
        s.units[owner].attackTargetID = nil
        s.units[owner].windupRemaining = nil
        s.units[owner].moveIntent = .none
        if Kit.scheduledCount(s, caster: owner, code: Code.ultRelease) == 0 {
            Self.endCharge(&s, owner)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        // 突進が止められた: 到着の処理が呼ばれないので記録を捨てる。アビス強化の致命の一撃なら消費したレイジを返す
        if k.diasDashAbyss == 1 {
            s.units[owner].hero!.kit!.diasRage = min(Tune.rageMax, k.diasRage + Tune.abyssCost)
            s.units[owner].hero!.kit!.diasAbyssUses = max(0, k.diasAbyssUses - 1)
        }
        s.units[owner].hero!.kit!.diasDashAbyss = 0
        s.units[owner].hero!.kit!.diasDashTargetID = 0
    }

    // MARK: - C. パッシブ（紅血の拳）

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard let k = s.units[attacker].hero?.kit else { return }
        let swings = k.diasSwings + 1
        guard swings >= Tune.circleEvery else {
            s.units[attacker].hero!.kit!.diasSwings = swings
            return
        }
        s.units[attacker].hero!.kit!.diasSwings = 0
        s.units[attacker].hero!.kit!.diasCircles += 1
        // 円撃: 主対象は plan（会心込みの攻撃力 × 倍率）、周りの敵には同じダメージを別に与える（吸血は主対象だけ）。
        // 強化ダメージはタワー（構造物）には乗らない（公式）: 主対象が構造物なら通常攻撃のダメージのまま、周りには倍率込み
        let level = s.units[attacker].hero?.level ?? 1
        let circle = plan.payload.damage * Self.circleRatio(level: level)
        if !s.units[target].isStructure { plan.payload.damage = circle }
        // 円撃は装備の攻撃エフェクト（命中時効果）を発動しない（公式）。吸血・クールダウン短縮は主対象に乗ったまま
        plan.payload.skipsItemOnHit = true
        let around = HitPayload(damage: circle, damageType: .physical, source: .basicAttack,
                                isCrit: plan.payload.isCrit, appliesOnHit: false)
        let center = s.units[attacker].pos
        let hit = Kit.hitAreaEach(&s, ctx, caster: attacker, center: center, radius: Tune.circleRadius,
                                  shape: .circle, excluding: target) { _, _ in around }
        // 回復: 最大 HP の 1.4〜2%。敵ヒーローが 1 体でも含まれていれば全量、ミニオン・モンスター・タワーだけなら半分
        let mainIsHero = s.units[target].kind == .hero
        let anyHero = mainIsHero || hit.contains { s.units[$0].kind == .hero }
        let maxHP = s.units[attacker].stats.maxHP
        let heal = maxHP * Self.circleHealRatio(level: level) * (anyHero ? 1 : Tune.circleHealNonHero)
        plan.payload.effects.append(.healOwner(flat: heal, ratioOfDealt: 0))
        // 主対象がヒーローでなくても、周りの敵ヒーローに当たればクールダウンが縮む（主対象がヒーローなら onBasicAttackHit）
        if !mainIsHero, hit.contains(where: { s.units[$0].kind == .hero }) {
            Self.refundCooldowns(&s, ctx, attacker)
        }
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        guard s.units.indices.contains(target), s.units[target].kind == .hero else { return }
        Self.refundCooldowns(&s, ctx, attacker)
    }

    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double) {
        // 「ダメージを与えた」敵ヒーローへの命中。1 回の発動（S1 の連撃・S2 の 1/2 回目・奥義）につき 1 度だけ
        guard damage > 0, s.units.indices.contains(target), s.units[target].kind == .hero,
              let k = s.units[attacker].hero?.kit, k.diasRefundedSerial != k.diasCastSerial else { return }
        s.units[attacker].hero!.kit!.diasRefundedSerial = k.diasCastSerial
        Self.refundCooldowns(&s, ctx, attacker, seconds: Tune.skillCooldownRefund)
    }

    // MARK: - D. ボット

    /// 奥義（0.5 秒の溜めの間は動けず、向きは発動時に固定）: 交戦中の敵ヒーローが射程の手前に居れば、汎用の関門
    /// （倒せる・2 体以上）を待たずに、溜めのあいだの敵の動きを読んだ向きへ今撃つ。それ以外は従来どおり。
    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        guard slot == .ultimate, fighting else { return .useDefault }
        let foe = s.units[target]
        guard foe.kind == .hero, (s.units[bot].hero?.kit?.diasUltCharging ?? 0) == 0 else { return .useDefault }
        let me = s.units[bot].pos
        guard me.distance(to: foe.pos) <= Tune.ultBotReach else { return .useDefault }
        // 直前の tick の動き（prevPos → pos）が続くものとして、溜めの間に進む分を足す（敵の移動速度の 0.5 秒分まで）
        let step = foe.pos - foe.prevPos
        let ahead = (step * (Tune.ultCharge / Balance.dt)).clamped(maxLength: max(0, foe.stats.moveSpeed) * Tune.ultCharge)
        let aim = foe.pos + ahead
        // 動きを読んだ先も線に収まらないなら、今の位置へ撃つ
        let dir = (me.distance(to: aim) <= Tune.ultReach ? aim - me : foe.pos - me).normalized
        guard dir != .zero else { return .useDefault }
        return .castNow(.direction(dir))
    }

    /// ミニオン・ジャングルの集団にも紅蓮の踏込（S2 の 1 回目）を使ってよいか。HP が半分以上で、突進の先が
    /// 敵のタワー・コアの射程に入らないときだけ。
    func botFarm(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 center: Vec2, count: Int) -> Bool {
        guard slot == .skill2, s.units[bot].hpRatio >= 0.5 else { return false }
        for u in s.units where u.isStructure && u.isAlive && u.team != s.units[bot].team {
            let r = Balance.towerRange + Balance.heroRadius + 120
            if u.pos.distanceSquared(to: center) <= r * r { return false }
        }
        return true
    }

    // MARK: - 部品

    /// レイジを 50 消費してアビス強化にできるか（できたら消費して true）。
    private static func spendRage(_ s: inout SimState, _ i: Int) -> Bool {
        guard let rage = s.units[i].hero?.kit?.diasRage, rage >= Tune.abyssCost - 1e-9 else { return false }
        s.units[i].hero!.kit!.diasRage = max(0, rage - Tune.abyssCost)
        s.units[i].hero!.kit!.diasAbyssUses += 1
        return true
    }

    /// S1・S2 のクールダウンを縮める（練習場の noCooldowns は Kit.refundCooldown が尊重）。
    private static func refundCooldowns(_ s: inout SimState, _ ctx: SimContext, _ i: Int, seconds: Double = Tune.cooldownRefund) {
        Kit.refundCooldown(&s, ctx, caster: i, slot: .skill1, seconds: seconds)
        Kit.refundCooldown(&s, ctx, caster: i, slot: .skill2, seconds: seconds)
    }

    private static func endCharge(_ s: inout SimState, _ i: Int) {
        s.units[i].hero?.kit?.diasUltCharging = 0
        s.units[i].hero?.kit?.diasUltCharge = 0
        s.units[i].statuses.removeAll { ($0.kind == .root || $0.kind == .channeling) && $0.tag == Tune.ultChannelTag }
    }

    /// 生きている敵ユニット（id から）。
    private static func liveEnemy(_ s: SimState, _ owner: Int, id: EntityID) -> Int? {
        guard id != 0, let t = s.index(of: id), CombatSystem.isLiving(s, t), s.units[t].team != s.units[owner].team,
              !s.units[t].has(.untargetable) else { return nil }
        return t
    }

    /// 突進の終わりに、対象が術者の近く（半径の和 + 余裕）に居るか。
    private static func isNear(_ s: SimState, _ owner: Int, _ t: Int, slack: Double) -> Bool {
        let reach = s.units[owner].radius + s.units[t].radius + slack
        return s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach
    }

    static func lostHealth(_ u: Unit) -> Double { max(0, u.stats.maxHP - max(0, u.hp)) }

    static func rageRate(level: Int) -> Double {
        lerp(Tune.rageGain.0, Tune.rageGain.1, level: level)
    }

    static func circleRatio(level: Int) -> Double { lerp(Tune.circleRatio.0, Tune.circleRatio.1, level: level) }
    static func circleHealRatio(level: Int) -> Double { lerp(Tune.circleHeal.0, Tune.circleHeal.1, level: level) }

    /// 公式の基礎ダメージ（ランクで補間）を sim の通常の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), slot: SkillSlot, scale: Double, rank: Int) -> Double {
        rankLerp(table.0, table.1, rank: rank, maxRank: slot.maxRank) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の「+N% 物理攻撃」を sim の通常の式（× skillAttackScalingFactor × スロット倍率 × 換算）に通した割合（%）。
    static func attackPercent(_ ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * Balance.skillAttackScalingFactor * Balance.Skills.damageScale(slot) * scale * 100
    }

    /// スキル1 の 1 発目のダメージ（240 → 520 + 60% 物理攻撃。減衰なし）。
    static func burstDamage(rank: Int, stats: Stats) -> Double {
        (rankLerp(Tune.burstBase.0, Tune.burstBase.1, rank: rank, maxRank: SkillSlot.skill1.maxRank)
            + Tune.burstAttackRatio * stats.attack * Balance.skillAttackScalingFactor)
            * Balance.Skills.damageScale(.skill1) * Tune.burstScale
    }

    /// 奥義の基礎ダメージ（650 / 950 / 1250 を換算。追加物理攻撃の分は発動時に足す）。
    static func ultDamage(rank: Int) -> Double {
        scaledBase(Tune.ultBase, slot: .ultimate, scale: Tune.ultScale, rank: rank)
    }

    /// 奥義の 1 体ぶんのダメージ（防御で軽減する前）: 基礎 + 失った HP の 20%。ヒーロー以外は上限 cap まで。
    static func ultHitDamage(flat: Double, lostHealth: Double, isHero: Bool, cap: Double) -> Double {
        let raw = flat + max(0, lostHealth) * Tune.ultLostHealth
        return isHero ? raw : min(raw, cap)
    }

    /// 奥義のヒーロー以外へのダメージの上限（1500 / 2000 / 2500 を基礎と同じ換算に通す）。
    static func ultNonHeroCap(rank: Int) -> Double {
        scaledBase(Tune.ultNonHeroCap, slot: .ultimate, scale: Tune.ultScale, rank: rank)
    }

    /// 追加物理攻撃（物理攻撃 − レベルの基礎値。装備・バフで増えた分）。
    static func extraAttack(_ u: Unit) -> Double { max(0, u.stats.attack - u.baseStats.attack) }

    /// 「+N% 追加物理攻撃」の分のダメージ（sim の式: 係数 × 追加物理攻撃 × skillAttackScalingFactor × スロット倍率 × 換算）。
    static func extraAttackDamage(_ s: SimState, _ i: Int, ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * extraAttack(s.units[i]) * Balance.skillAttackScalingFactor * Balance.Skills.damageScale(slot) * scale
    }

    /// ランク（1...maxRank）で線形補間。
    private static func rankLerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    /// レベル（1...maxLevel）で線形補間。
    private static func lerp(_ a: Double, _ b: Double, level: Int) -> Double {
        let t = Double(min(max(1, level), Balance.maxLevel) - 1) / Double(Balance.maxLevel - 1)
        return a + (b - a) * t
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、CD 短縮を掛ける（全体倍率 cooldownScale は 1.0 = MLBB の秒数のまま）。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        let sec: Double
        if maxRank > 1 {
            let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
            sec = range.0 + (range.1 - range.0) * t
        } else {
            sec = range.0
        }
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H032", slot: slot)?.skillID
    }

    /// 致命の一撃の対象: 指定ユニット → 指定地点に近い敵 → 向きに近い敵 → 自動（HP + シールド最小）。敵ヒーローだけ（reach 以内・視認中）。
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
