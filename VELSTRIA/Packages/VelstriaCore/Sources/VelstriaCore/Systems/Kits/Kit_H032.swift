import Foundation

// 担当: kit-H032（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Dyrroth.md）
// H032 赤拳のディアス = Velstria 版の Dyrroth（MLBB。調査: docs/kits/Dyrroth.md、対応表: 同ファイル末尾）。
// デュエリスト（EXP）の近接。キットはロールの汎用パッシブ（通常攻撃の攻撃速度スタック）を置き換える。
//   パッシブ 紅血の拳（Wrath of the Abyss）— レイジ（0〜100）が時間でたまる（毎秒 2〜5%、レベルで増える。Velstria は CD が半分なので ×2）。
//                           50 以上でスキル1・スキル2 が「アビス強化」になり、使うと 50 を消費する。
//                           HUD のバッジ = Int(レイジ / 50)（0〜2）。演出（SkillFXDirector）はバッジが増えた瞬間（50・100）だけ出す
//                           通常攻撃 2 回に 1 回は円撃（Circle Strike）: 周囲の敵へ攻撃力の 150〜180%、最大 HP の 4.2〜6% 回復（MLBB 7〜10% の 0.6 倍）
//                           （ミニオン・タワーだけが相手なら半分）。敵ヒーローにダメージを与えるたび S1・S2 の CD が縮む。
//   S1   赤拳連斬（Burst Strike）— 前方の扇へ 3 連（アビス強化は 5 連）の衝撃。同じ敵への 2 発目以降は減衰、ミニオンへは 60%。
//                           鈍足 25%（アビス強化 50%）1.5 秒。アビス強化は射程が伸び、合計ダメージ 140%。
//   S2   紅蓮の踏込（Spectre Step）— 1 回目: 指定方向へ突進し、最初に当たった敵（ヒーロー・ミニオン・モンスター）で止まって
//                           ダメージ + 軽く押し出す。3 秒以内の再使用（同じ castSkill）で 2 回目の致命の一撃:
//                           敵ヒーローへ飛びかかり、ダメージ + 物理防御 −40%（アビス強化 −60% + 鈍足、射程と威力 150%）4 秒。
//   奥義 奈落の一撃（Abysm Strike）— 0.5 秒の溜め（その場から動けない。CC では止まらず、suppress だけで中断）のあと、
//                           前方 650 の直線上（半幅 140）の敵へダメージ + 対象の失った HP の 22.5% + 鈍足 55% 0.8 秒。
//                           ボットは溜めの間の敵の動きを読んで撃つ（botCast。敵ヒーローに届けば汎用の関門を待たない）。
//
// 状態（KitState）:
//   reals[0] = レイジ（0..100）       reals[1] = 突進（S2 の 1・2 回目）の命中ダメージ   reals[2..3] = 奥義の向き
//   reals[4] = 奥義の基礎ダメージ（発動時に確定）
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
        /// 毎秒のレイジ（MLBB: 2〜5%/s をレベル 1〜最大で補間）に掛ける時間の倍率。Velstria はスキルの CD が半分
        /// （Balance.Skills.cooldownScale）なので、同じ「CD 1 回あたりのレイジ」になるよう 1 / cooldownScale 倍にする。
        static let rageTimeScale = 1 / Balance.Skills.cooldownScale
        static let rageGain = (2.0, 5.0)
        /// アビス強化に要るレイジと、使ったときの消費量（調査: 50% で強化、消費量は不明 → 50 を選んだ）。
        static let abyssCost = 50.0

        // パッシブ: 円撃（Circle Strike）
        static let circleEvery = 2
        static let circleRatio = (1.5, 1.8)
        /// MLBB は最大 HP の 7〜10%。Velstria の TTK は MLBB よりずっと短い（2.5〜15 秒）ので 0.4 倍前後にした（3〜4%）。
        static let circleHeal = (0.03, 0.04)
        /// 円撃の半径（術者の中心から。対象の半径は別に足す）。通常攻撃の射程 150 より少し広い（MLBB 1.7 → 2.0 の比）。
        static let circleRadius = 190.0
        /// ミニオン・モンスター・タワーだけが相手のときの回復の倍率。
        static let circleHealNonHero = 0.5

        // パッシブ: 敵ヒーローにダメージを与えるたびに S1・S2 のクールダウンを縮める秒数。
        // 通常攻撃・円撃の命中 = cooldownRefund、スキルの命中（1 回の発動につき 1 度）= skillCooldownRefund。
        // MLBB は 1 秒。Velstria は CD が半分（cooldownScale 0.5）なので 0.5 秒が素直な換算だが、1v1 の勝率が全員総当たりで
        // 汎用の Duelist より上へ偏った（スキルの稼働率が上がる）ので、通常攻撃・円撃は 0.3、スキルの命中は 0.05 に抑えた
        // （docs/kits/Dyrroth.md の対応表）。
        static let cooldownRefund = 0.3
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
        /// 同じ敵への連続ヒットの減衰（1 発目 = 1.0 を基準にした重み。合計で正規化する）。
        static let burstWeights: [Double] = [1.0, 0.7, 0.5]
        static let burstWeightsAbyss: [Double] = [1.0, 0.8, 0.65, 0.5, 0.4]
        /// ミニオンへのダメージ倍率。
        static let burstMinionFactor = 0.6
        static let burstSlow = 0.25
        static let burstSlowAbyss = 0.50
        static let burstSlowDuration = 1.5
        static let burstSlowTag = KitTags.buff("H032", "burstSlow")
        /// 通常版の合計ダメージ ÷ 汎用 S1 のダメージ。アビス強化は 140%（調査: 「元のダメージの 140%」を合計に掛ける = 0.98）。
        /// 予算の下限 0.8 より低い 0.70: クールダウン短縮・アビス強化・円撃の上乗せがあり、0.82 だと全員総当たりの勝率が汎用の
        /// Duelist より Lv1 で +22pt・Lv12 で +20pt 高く、開幕 3 秒の火力も汎用の 2.1〜4.9 倍だった（0.70 で +11 / +11、1.8〜1.9 倍）。
        static let burstRatio = 0.70
        static let abyssBurstMultiplier = 1.4

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
        /// 1 回目と 2 回目の取り分（MLBB の 230 : 345 = 0.4 : 0.6）。合計 ÷ 汎用 S2 のダメージ = spectreRatio。
        static let dashShare = 0.4
        static let spectreRatio = 0.82
        static let abyssFatalMultiplier = 1.5
        static let shred = 0.40
        static let shredAbyss = 0.60
        static let shredDuration = 4.0
        static let shredTag = KitTags.buff("H032", "shred")
        /// アビス強化の致命の一撃の追加の鈍足（調査の「90%」は未確認なので控えめに選んだ）。
        static let fatalSlowAbyss = 0.5
        static let fatalSlowDuration = 1.2
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
        static let ultLostHealth = 0.225
        static let ultSlow = 0.55
        static let ultSlowDuration = 0.8
        static let ultSlowTag = KitTags.buff("H032", "ultSlow")
        static let ultChannelTag = KitTags.buff("H032", "channel")
        /// 汎用の奥義（Duelist = 3 連撃）の合計ダメージに対する倍率（ランクごと。MLBB の 650/950/1250 の傾きを範囲内で写した）。
        static let ultRatio = 0.90
        static let ultRankFactor: [Double] = [0.9, 1.0, 1.1]

        // クールダウン（MLBB 秒 → ランク間を線形補間 → Balance.Skills.cooldownScale を掛ける）
        static let burstCooldown = (6.0, 4.0)
        static let spectreCooldown = (6.0, 6.0)
        static let ultCooldown = (36.0, 28.0)
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
            n.extras = [KitStat(key: "rageMin", value: Tune.rageGain.0 * Tune.rageTimeScale),
                        KitStat(key: "rageMax", value: Tune.rageGain.1 * Tune.rageTimeScale),
                        KitStat(key: "circleMin", value: Tune.circleRatio.0 * 100),
                        KitStat(key: "circleMax", value: Tune.circleRatio.1 * 100)]
        case .skill1:
            let total = base.damage * Tune.burstRatio
            n.hits = Tune.burstCount
            n.damage = total / Double(Tune.burstCount)
            n.cooldown = Self.cooldown(Tune.burstCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccDuration = Tune.burstSlowDuration
            n.extras = [KitStat(key: "abyssHits", value: Double(Tune.burstCountAbyss)),
                        KitStat(key: "abyssTotal", value: total * Tune.abyssBurstMultiplier),
                        KitStat(key: "slow", value: Tune.burstSlow * 100),
                        KitStat(key: "abyssSlow", value: Tune.burstSlowAbyss * 100)]
        case .skill2:
            let total = base.damage * Tune.spectreRatio
            let dash = total * Tune.dashShare
            let fatal = total - dash
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
                        KitStat(key: "abyssShred", value: Tune.shredAbyss * 100)]
        case .ultimate:
            n.hits = 1
            n.damage = Self.ultDamage(base: base, rank: rank)
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
                        KitStat(key: "slowDuration", value: Tune.ultSlowDuration)]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        let heal = "\(String(format: "%g", Tune.circleHeal.0 * 100))〜\(String(format: "%g", Tune.circleHeal.1 * 100))"
        let abyss = Int(Tune.abyssCost)
        switch slot {
        case .passive:
            let hit = String(format: "%g", Tune.cooldownRefund)
            let skillHit = String(format: "%g", Tune.skillCooldownRefund)
            return KitText(
                ja: "レイジが時間とともにたまる（毎秒{x0}〜{x1}%、レベルが高いほど速い。最大\(Int(Tune.rageMax))）。\(abyss)以上あると、スキル1とスキル2が「アビス強化」になり、使うとレイジを\(abyss)消費する。"
                    + "通常攻撃\(Tune.circleEvery)回に1回は円撃になり、周囲の敵に攻撃力の{x2}〜{x3}%の物理ダメージを与えて最大HPの\(heal)%を回復する（ミニオンとタワーだけが相手なら回復は半分）。"
                    + "敵ヒーローに通常攻撃（円撃を含む）を当てるたびにスキル1とスキル2のクールダウンが\(hit)秒、スキルを当てるたび（1回の発動につき1度）に\(skillHit)秒縮む。",
                en: "Rage builds over time ({x0}-{x1}% per second, faster at higher levels; max \(Int(Tune.rageMax))). With \(abyss) or more, Skill 1 and Skill 2 become Abyss Enhanced and spend \(abyss) Rage when used. "
                    + "Every \(Tune.circleEvery)nd basic attack is a Circle Strike that hits nearby enemies for {x2}-{x3}% of attack as physical damage and heals \(heal)% of max HP (half against only minions and turrets). "
                    + "Each time a basic attack (including a Circle Strike) hits an enemy hero, Skill 1 and Skill 2 cooldowns are reduced by \(hit)s; each time a skill hits an enemy hero (once per cast), by \(skillHit)s.")
        case .skill1:
            return KitText(
                ja: "前方の扇へ衝撃を{hits}回放ち、合計{total}ダメージ（同じ敵への2発目以降は減衰、ミニオンには\(Int(Tune.burstMinionFactor * 100))%）。{x2}%の鈍足を\(String(format: "%g", Tune.burstSlowDuration))秒与える。"
                    + "アビス強化: 射程が\(Int(Tune.burstReachAbyss))に伸び、{x0}回・合計{x1}ダメージ、鈍足は{x3}%。クールダウン{cd}秒。",
                en: "Release {hits} bursts into the cone ahead for {total} damage in total (repeat hits on the same target are reduced; minions take \(Int(Tune.burstMinionFactor * 100))%), slowing by {x2}% for \(String(format: "%g", Tune.burstSlowDuration))s. "
                    + "Abyss Enhanced: range extends to \(Int(Tune.burstReachAbyss)), {x0} bursts for {x1} total damage, slow {x3}%. Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "指定方向へ突進し、最初に当たった敵（ヒーロー・ミニオン・モンスター）の手前で止まって{damage}ダメージを与え、わずかに押し出す。"
                    + "\(String(format: "%g", Tune.recastWindow))秒以内にもう一度使うと、敵ヒーローへ飛びかかって{x0}ダメージ、{x1}%の防御ダウン（\(Int(Tune.shredDuration))秒）。"
                    + "アビス強化: 射程が\(Int(Tune.fatalReachAbyss))に伸び、{x2}ダメージ、防御ダウン{x3}%、さらに\(Int(Tune.fatalSlowAbyss * 100))%の鈍足。クールダウン{cd}秒。",
                en: "Dash in a direction, stopping at the first enemy (hero, minion or monster) to deal {damage} damage and knock it back slightly. "
                    + "Use again within \(String(format: "%g", Tune.recastWindow))s to leap at an enemy hero for {x0} damage and reduce its defense by {x1}% for \(Int(Tune.shredDuration))s. "
                    + "Abyss Enhanced: reach extends to \(Int(Tune.fatalReachAbyss)), {x2} damage, {x3}% defense reduction and an extra \(Int(Tune.fatalSlowAbyss * 100))% slow. Cooldown {cd}s.")
        case .ultimate:
            return KitText(
                ja: "{x1}秒の溜め（その場から動けない。スタンなどでは止まらず、制圧（サプレス）でのみ中断される）のあと、前方{range}の直線上の敵に{damage}ダメージ"
                    + "＋対象の失ったHPの{x0}%を与え、{x2}%の鈍足を{x3}秒与える（失ったHPの加算は敵ヒーローのみ）。クールダウン{cd}秒。",
                en: "After a {x1}s charge (rooted in place; stuns do not stop it, only suppression interrupts it), strike enemies on the line {range} ahead for {damage} damage "
                    + "plus {x0}% of the target's lost HP (enemy heroes only), slowing by {x2}% for {x3}s. Cooldown {cd}s.")
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
        let weights = abyss ? Tune.burstWeightsAbyss : Tune.burstWeights
        let interval = abyss ? Tune.burstIntervalAbyss : Tune.burstInterval
        let reach = abyss ? Tune.burstReachAbyss : Tune.burstReach
        // 通常版の合計（damage は 1 発あたりの平均）。アビス強化は合計の 140% を 5 発へ配る
        let total = c.numbers.damage * Double(Tune.burstCount) * (abyss ? Tune.abyssBurstMultiplier : 1)
        let sum = weights.reduce(0, +)
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
                         param: total * weights[k] / sum, point: dir, interruptible: true)
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
        s.units[i].hero!.kit!.diasDashDamage = c.numbers.damage * (abyss ? Tune.abyssFatalMultiplier : 1)
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

    /// 奥義の解放: 今の位置から固定の向きの直線上の敵へ、基礎ダメージ + （敵ヒーローは）失った HP の割合。suppress 中は不発。
    private func release(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let kit = s.units[owner].hero?.kit, kit.diasUltCharging == 1 else { return }
        Self.endCharge(&s, owner)
        guard !s.units[owner].has(.suppress) else { return }
        let id = s.units[owner].id
        let slow = StatusEffect(kind: .slow, duration: Tune.ultSlowDuration, magnitude: Tune.ultSlow, sourceID: id,
                                tag: Tune.ultSlowTag)
        let skillID = Self.skillID(ctx, .ultimate)
        let flat = kit.diasUltDamage
        let center = s.units[owner].pos
        Kit.hitAreaEach(&s, ctx, caster: owner, center: center, radius: Tune.ultHalfWidth,
                        shape: .line(direction: kit.diasUltDirection, length: Tune.ultLineLength)) { st, j in
            let lost = st.units[j].kind == .hero ? Self.lostHealth(st.units[j]) * Tune.ultLostHealth : 0
            var p = HitPayload(damage: flat + lost, damageType: .physical, source: .skill(.ultimate),
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
        // 円撃: 主対象は plan（会心込みの攻撃力 × 倍率）、周りの敵には同じダメージを別に与える（命中時効果・吸血は主対象だけ）
        let level = s.units[attacker].hero?.level ?? 1
        plan.payload.damage *= Self.circleRatio(level: level)
        let around = HitPayload(damage: plan.payload.damage, damageType: .physical, source: .basicAttack,
                                isCrit: plan.payload.isCrit, appliesOnHit: false)
        let center = s.units[attacker].pos
        let hit = Kit.hitAreaEach(&s, ctx, caster: attacker, center: center, radius: Tune.circleRadius,
                                  shape: .circle, excluding: target) { _, _ in around }
        // 回復: 最大 HP の 4.2〜6%。敵ヒーローが 1 体でも含まれていれば全量、ミニオン・モンスター・タワーだけなら半分
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
        lerp(Tune.rageGain.0, Tune.rageGain.1, level: level) * Tune.rageTimeScale
    }

    static func circleRatio(level: Int) -> Double { lerp(Tune.circleRatio.0, Tune.circleRatio.1, level: level) }
    static func circleHealRatio(level: Int) -> Double { lerp(Tune.circleHeal.0, Tune.circleHeal.1, level: level) }

    /// 基礎ダメージ（汎用の連撃の合計 × 倍率 × ランク別の係数）。
    static func ultDamage(base: SkillNumbers, rank: Int) -> Double {
        let r = min(max(1, rank), Tune.ultRankFactor.count)
        return base.totalDamage * Tune.ultRatio * Tune.ultRankFactor[r - 1]
    }

    /// レベル（1...maxLevel）で線形補間。
    private static func lerp(_ a: Double, _ b: Double, level: Int) -> Double {
        let t = Double(min(max(1, level), Balance.maxLevel) - 1) / Double(Balance.maxLevel - 1)
        return a + (b - a) * t
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、Velstria の全体倍率と CD 短縮を掛ける。
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
