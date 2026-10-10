import Foundation

// 担当: kit-H028（docs/SKILL_KITS.md / docs/NEW_HEROES.md）
// H028 断空のザイル = Velstria 版の Saber（MLBB。調査: docs/kits/Saber.md、対応表: 同ファイル末尾）。
// 数値の正は MLBB の日本語クライアントのスキル詳細（docs/kits/Saber.md の「公式（日本語クライアント）の数値」。Fandom と違うところはこちらが優先）。
// アサシン（近接 150・Energy）。キットはロールの汎用パッシブ（奇襲ボーナス・キル/アシストの全 CD 短縮）を置き換える。
//   パッシブ 空断の理（Enemy's Bane）— ダメージを与えるたび（通常攻撃・スキル）に相手の物理防御を下げる。5 層・5 秒、
//                                      1 層あたり 3 → 8（公式のレベル別の表: Lv1〜3 = 3、…、Lv15 = 8）。
//   S1   環剣（Flying Sword）        — 5 本の剣が 5 秒間 周囲を回り、触れた敵に 75 → 125（+25% 追加物理攻撃）の接触ダメージ（0.5 秒ごと）。
//                                      周回中に通常攻撃/スキルでダメージを与えるたび、剣が対象へ飛んで「剣撃」200 → 300（+50% 追加）
//                                      （貫通した他の敵には 50%、ヒーロー以外には 50%）+ スキル1 のクールダウン −0.5 秒・スキル2 −1 秒。
//   S2   断空突進（Assault）         — 指定方向へ突進して通り道の敵に 75 → 150（+50% 追加）。次の通常攻撃が強化
//                                      （物理攻撃 120% + 75 → 150、鈍足 60%・1 秒、射程 250）。
//   奥義 三連断空（Triple Slash）     — 対象指定（敵ヒーロー）。突進して 1.2 秒打ち上げ（強靭 = CC 短縮の影響を受けない）、その間に 3 連撃
//                                      （120 / 170 / 220（+80% 追加）× 2 + 240 / 340 / 440（+160% 追加））。最初の 2 撃には S1 の剣撃が乗る
//                                      （3 撃目は乗らない）。突進はハード CC で、打ち上げたあとの連撃は制圧（suppress）でのみ中断される。
// 数値の換算: 公式の表を Velstria のランク（S1・S2 は 4 段、奥義は 3 段）へ線形補間し、sim の通常の式
//   (基礎 + 係数 × 追加物理攻撃 × skillAttackScalingFactor) × スロット倍率 にスキルごとの換算（Tune.*Scale）を掛ける（H029 と同じ）。
//   「追加物理攻撃」= 物理攻撃 − レベルの基礎値（Unit.baseStats。H032 と同じ）で、発動の時点で足す。numbers（HUD・説明文）は装備なしの値。
//   強化通常攻撃の 120% だけは総物理攻撃（公式の「物理攻撃」）。コスト・クールダウンもランクで補間。
// 再使用の窓は Saber に無いので使わない。
//
// 状態（KitState）:
//   ints[0]  = 奥義の段（0 = なし / 1 = 突進中 / 2 = 三連撃中）  ints[1] = 剣撃を出さない間 1（3 撃目の最中のみ）
//   ints[2]  = 剣撃を出した回数（累計。検証用）                  ints[3] = 奥義の三連撃が当たった回数（累計。検証用）
//   ints[4]  = 直近に防御ダウンを積んだ敵の層の数（パッシブのバッジ用）  ids[1] = その敵
//   timers[0] = 剣が周回している残り秒   timers[1] = 剣撃の最短間隔（同時に何本も飛ばさない）
//   timers[2] = S2 の強化通常攻撃の残り秒   timers[3] = 防御ダウンの層が残っている秒（バッジ。命中のたびに 5 秒へ戻る）
//   reals[0] = 接触ダメージ（1 回）  reals[1] = 剣撃ダメージ  reals[2] = 強化通常攻撃の基礎ダメージ（換算後）  reals[3] = 奥義の平均 1 撃
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
        /// 1 層あたりの防御ダウン（固定値）。公式のレベル別の表（Lv1〜15。式ではなく、あるレベルに達するたびに 1 ずつ増える）。
        static let baneByLevel: [Double] = [3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 7, 7, 7, 8]
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
        /// 公式（日本語クライアント）: 接触 75 → 125（+25% 追加物理攻撃）、剣撃 200 → 300（+50% 追加物理攻撃）。Lv1 → Lv6 を最大ランクへ線形補間。
        /// 「追加物理攻撃」= 装備・バフで増えた分（物理攻撃 − レベルの基礎値。Unit.baseStats）。発動の時点の値で足す（bonusAttack）。
        static let contactBase = (75.0, 125.0)
        static let contactAttackRatio = 0.25
        static let strikeBase = (200.0, 300.0)
        static let strikeAttackRatio = 0.5
        /// 公式の値 → Velstria の換算（接触と剣撃で共通。sim の通常の式 × スロット倍率の後ろに掛ける）。勝率で決めた（docs/kits/Saber.md の「日本語クライアントの数値へ」）。
        static let swordsScale = 0.14
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
        /// 剣撃がヒーロー以外の敵（ミニオン・中立モンスター）に与えるダメージの割合（公式 50%。練習場の人形はヒーロー扱い）。
        static let strikeNonHeroRatio = 0.5
        /// 剣撃 1 本あたりの S2 のクールダウン短縮（MLBB と同じ 1 秒。CD が MLBB の秒数なので換算しない）。
        static let chargeRefund = 1.0
        /// 剣撃 1 本あたりの S1 自身のクールダウン短縮（日本語クライアント: 0.5 秒）。
        static let swordsRefund = 0.5

        // S2 突進
        static let dashRange = 350.0
        static let dashSpeed = 1800.0
        /// 経路の当たり半径（対象の半径は別に足す）。
        static let dashWidth = 70.0
        /// 公式: 突進 75 → 150（+50% 追加物理攻撃）。強化通常攻撃は 75 → 150（+120% 物理攻撃 = 総物理攻撃）で通常攻撃を置き換える
        /// （= 通常攻撃のダメージ × 1.2 + 基礎。基礎は突進と同じ換算）。
        static let dashBase = (75.0, 150.0)
        static let dashAttackRatio = 0.5
        static let enhanceBase = (75.0, 150.0)
        static let enhanceAttackRatio = 1.2
        /// 公式の値 → Velstria の換算（突進と強化通常攻撃の基礎で共通）。勝率で決めた（docs/kits/Saber.md の「日本語クライアントの数値へ」）。
        static let chargeScale = 1.2
        /// 強化通常攻撃を撃てる時間（公式に記載なし。汎用の強化通常攻撃（blinkEmpower）に合わせた）。
        static let enhanceWindow = Balance.Skills.empowerDuration
        /// 強化通常攻撃の射程（公式 2.5 = 250。通常攻撃の射程 150 との差を、強化が残っている間だけ足す）。
        static let enhanceRange = 250.0
        static let enhanceRangeTag = KitTags.buff("H028", "enhanceRange")
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
        /// 1〜3 撃目の重み（公式 120 : 120 : 240、係数も 80% : 80% : 160% = 0.75 : 0.75 : 1.5。合計 3 = 平均 1 撃 × 3）。
        static let ultWeights: [Double] = [0.75, 0.75, 1.5]
        /// 公式（日本語クライアント）: 1・2 撃目 120 / 170 / 220（+80% 追加物理攻撃）、3 撃目 240 / 340 / 440（+160% 追加物理攻撃）
        /// = 1・2 撃目のちょうど 2 倍（Fandom の 120 / 150 / 180（+100%）は誤り）。
        static let ultStrikeBase = (120.0, 220.0)
        static let ultStrikeAttackRatio = 0.8
        /// 公式の値 → Velstria の換算。勝率で決めた（docs/kits/Saber.md の「日本語クライアントの数値へ」）。
        static let ultScale = 0.55
        static let channelTag = KitTags.buff("H028", "channel")
        /// ボットが関門を待たずに奥義を撃つ、敵ヒーローの HP の割合の上限（打ち上げ中の 3 連撃 + 防御ダウンで削り切れる目安）。
        static let botExecuteRatio = 0.6

        // クールダウン（公式の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
        /// S1 は全ランク 10 秒（日本語クライアント。Fandom の 9 秒は誤り）。持続 5 秒、剣撃 1 本ごとに 0.5 秒縮む。
        static let swordsCooldown = (10.0, 10.0)
        static let chargeCooldown = (7.0, 7.0)
        static let ultCooldown = (44.0, 36.0)
        // コスト（公式のマナ。Energy のヒーローなので HeroKits.resourceCost で × energyCostMultiplier）
        /// 日本語クライアント: S1 60 → 85、S2 40 → 60、奥義 100 / 120 / 140（Fandom の S1 75 → 125・S2 70 → 45 は誤り）。
        static let swordsCost = (60.0, 85.0)
        static let chargeCost = (40.0, 60.0)
        static let ultCost = (100.0, 140.0)
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
            n.damage = Self.contactDamage(rank: rank)
            n.cc = .none
            n.ccDuration = 0
            n.cooldown = Self.cooldown(Tune.swordsCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "strikeDamage", value: Self.strikeDamage(rank: rank).rounded()),
                        KitStat(key: "duration", value: Tune.swordsDuration),
                        KitStat(key: "refund", value: Tune.chargeRefund),
                        KitStat(key: "passPercent", value: Tune.strikePassRatio * 100),
                        KitStat(key: "nonHeroPercent", value: Tune.strikeNonHeroRatio * 100),
                        KitStat(key: "base", value: Self.scaledBase(Tune.contactBase, slot: .skill1, scale: Tune.swordsScale,
                                                                    rank: rank, maxRank: slot.maxRank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.contactAttackRatio, slot: .skill1,
                                                                         scale: Tune.swordsScale).rounded()),
                        KitStat(key: "strikeBase", value: Self.scaledBase(Tune.strikeBase, slot: .skill1, scale: Tune.swordsScale,
                                                                          rank: rank, maxRank: slot.maxRank).rounded()),
                        KitStat(key: "strikePct", value: Self.attackPercent(Tune.strikeAttackRatio, slot: .skill1,
                                                                            scale: Tune.swordsScale).rounded()),
                        KitStat(key: "selfRefund", value: Tune.swordsRefund)]
        case .skill2:
            n.hits = 1
            n.damage = Self.dashDamage(rank: rank)
            // 鈍足は強化通常攻撃につく
            n.cc = .slow
            n.ccDuration = Tune.slowDuration
            n.cooldown = Self.cooldown(Tune.chargeCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            let enhance = Self.enhanceBaseDamage(rank: rank)
            n.extras = [KitStat(key: "enhanceDamage", value: (stats.attack * Tune.enhanceAttackRatio + enhance).rounded()),
                        KitStat(key: "slowPercent", value: Tune.slowAmount * 100),
                        KitStat(key: "slowDuration", value: Tune.slowDuration),
                        KitStat(key: "window", value: Tune.enhanceWindow),
                        KitStat(key: "base", value: Self.scaledBase(Tune.dashBase, slot: .skill2, scale: Tune.chargeScale,
                                                                    rank: rank, maxRank: slot.maxRank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.dashAttackRatio, slot: .skill2,
                                                                         scale: Tune.chargeScale).rounded()),
                        KitStat(key: "enhanceBase", value: enhance.rounded()),
                        KitStat(key: "enhancePct", value: Tune.enhanceAttackRatio * 100),
                        KitStat(key: "enhanceReach", value: Tune.enhanceRange / hero.attackRange)]
        case .ultimate:
            n.hits = Tune.strikeCount
            // 平均 1 撃（1・2 撃目 = × 0.75、3 撃目 = × 1.5）
            n.damage = Self.ultStrikeDamage(rank: rank) / Tune.ultWeights[0]
            n.missingHealthRatio = 0
            n.cc = .knockback
            n.ccIsUltimate = true
            n.ccDuration = Tune.airborne
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            let strikeBase = Self.scaledBase(Tune.ultStrikeBase, slot: .ultimate, scale: Tune.ultScale, rank: rank,
                                             maxRank: slot.maxRank)
            let strikePct = Self.attackPercent(Tune.ultStrikeAttackRatio, slot: .ultimate, scale: Tune.ultScale)
            let heavy = Tune.ultWeights[2] / Tune.ultWeights[0]
            n.extras = [KitStat(key: "strike1", value: (n.damage * Tune.ultWeights[0]).rounded()),
                        KitStat(key: "strike3", value: (n.damage * Tune.ultWeights[2]).rounded()),
                        KitStat(key: "airborne", value: Tune.airborne),
                        KitStat(key: "interval", value: Tune.ultInterval),
                        KitStat(key: "base", value: strikeBase.rounded()),
                        KitStat(key: "atkPct", value: strikePct.rounded()),
                        KitStat(key: "base3", value: (strikeBase * heavy).rounded()),
                        KitStat(key: "atkPct3", value: (strikePct * heavy).rounded())]
        }
        return n
    }

    /// ランクごとのコスト（公式のマナ: S1 60 → 85、S2 40 → 60、奥義 100 / 120 / 140。Energy なので × energyCostMultiplier）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: (Double, Double)
        switch slot {
        case .skill1: table = Tune.swordsCost
        case .skill2: table = Tune.chargeCost
        case .ultimate: table = Tune.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Self.lerp(table.0, table.1, rank: rank, maxRank: slot.maxRank), hero: hero)
    }

    /// 説明文は公式（日本語クライアント）の文の構造に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%追加物理攻撃) は sim の式に換算した値）。
    /// 名前は master のもの（フライングソード = 環剣、アサルト = 断空突進、剣の攻撃 = 剣撃）。
    func text(slot: SkillSlot) -> KitText? {
        let gap = String(format: "%g", Tune.strikeGap)
        switch slot {
        case .passive:
            return KitText(
                ja: "ダメージを与えるたびに、対象の物理防御を{duration}秒間{baneMin}-{baneMax}低下させる（レベルに応じて増加。最大{stacks}スタック）。\n\n"
                    + "防御を下げるのは通常攻撃とスキルのダメージで、ミニオンには積まれない。",
                en: "Each time Zail deals damage, the target's Physical Defense is reduced by {baneMin}-{baneMax} for {duration}s (grows with level; up to {stacks} stacks).\n\n"
                    + "Only basic attack and skill damage reduce defense, and it does not apply to minions.",
                tags: [KitTag.debuff])
        case .skill1:
            return KitText(
                ja: "自身の周囲を旋回する剣を5本放ち、命中した周囲の敵に{base}(+{atkPct}%追加物理攻撃)の物理ダメージを与える（0.5秒ごと、最大{hits}回）。効果時間（{duration}秒）終了後、剣は自身のもとへ戻る。\n\n"
                    + "発動中、通常攻撃またはスキルでダメージを与えるたびに剣撃を放つ（\(gap)秒に1回まで）。剣撃は対象に{strikeBase}(+{strikePct}%追加物理攻撃)の物理ダメージを与え、進路上の敵に{passPercent}%のダメージを与える（ヒーロー以外の敵へのダメージは{nonHeroPercent}%に低下）。剣撃ごとに、環剣のクールダウンが{selfRefund}秒、断空突進のクールダウンが{refund}秒短縮される。",
                en: "Release 5 swords that orbit around Zail, dealing {base} (+{atkPct}% Extra Physical Attack) physical damage to nearby enemies hit (every 0.5s, up to {hits} times). When the effect ends ({duration}s), the swords return to Zail.\n\n"
                    + "While active, each time Zail deals damage with a basic attack or a skill, a sword strike flies at the target (at most once every \(gap)s), dealing {strikeBase} (+{strikePct}% Extra Physical Attack) physical damage to the target and {passPercent}% damage to enemies in its path (damage to non-hero enemies is reduced to {nonHeroPercent}%). Each sword strike reduces the cooldown of this skill by {selfRefund}s and of Charge by {refund}s.",
                tags: [KitTag.aoe, KitTag.buff])
        case .skill2:
            return KitText(
                ja: "指定方向へ突撃し、進路上の敵に{base}(+{atkPct}%追加物理攻撃)の物理ダメージを与える。\n\n"
                    + "突撃後、強化された通常攻撃を獲得する（{window}秒以内。射程は近接攻撃の約{enhanceReach}倍）。強化された通常攻撃は対象に{enhanceBase}(+{enhancePct}%物理攻撃)の物理ダメージを与え、移動速度を{slowDuration}秒間{slowPercent}%低下させる。",
                en: "Charge in the target direction, dealing {base} (+{atkPct}% Extra Physical Attack) physical damage to enemies along the way.\n\n"
                    + "After the charge, Zail gains an enhanced basic attack (within {window}s, reaching about {enhanceReach}x the melee attack range) that deals {enhanceBase} (+{enhancePct}% Physical Attack) physical damage to the target and reduces its Movement Speed by {slowPercent}% for {slowDuration}s.",
                tags: [KitTag.mobility])
        case .ultimate:
            return KitText(
                ja: "対象の敵ヒーローへ突撃し、{airborne}秒間ノックアップさせる（強靭＝コントロール時間短縮の影響を受けない）。\n\n"
                    + "ノックアップの間に対象を3回攻撃し、最初の2回はそれぞれ{base}(+{atkPct}%追加物理攻撃)の物理ダメージ、3回目は{base3}(+{atkPct3}%追加物理攻撃)の物理ダメージを与える。"
                    + "突撃の途中はコントロール効果で止められるが、ノックアップさせた後は制圧によってのみ中断される。",
                en: "Charge at the target enemy hero and knock them airborne for {airborne}s (not affected by Resilience, i.e. crowd-control reduction).\n\n"
                    + "Strike the target 3 times while airborne: the first two strikes deal {base} (+{atkPct}% Extra Physical Attack) physical damage each, and the third deals {base3} (+{atkPct3}% Extra Physical Attack). "
                    + "The charge can be stopped by crowd control, but once the target is airborne the skill can only be interrupted by suppression.",
                tags: [KitTag.burst, KitTag.disrupt])
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
        // 接触・剣撃のダメージ（公式 75 → 125 + 25% / 200 → 300 + 50% 追加物理攻撃を換算。発動した時点のランク・追加物理攻撃）
        let bonus = Self.bonusAttack(s.units[i])
        let pulse = Self.contactDamage(rank: n.rank, bonusAttack: bonus)
        s.units[i].hero!.kit!.zailSwordsRemaining = Tune.swordsDuration
        s.units[i].hero!.kit!.zailPulseDamage = pulse
        s.units[i].hero!.kit!.zailStrikeDamage = Self.strikeDamage(rank: n.rank, bonusAttack: bonus)
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing,
                     duration: Tune.swordsDuration, count: Tune.swordCount)
        Kit.strikeSequence(&s, caster: i, slot: .skill1, code: Code.pulse, count: Tune.pulseCount,
                           interval: Tune.pulseInterval, firstDelay: Tune.pulseInterval, param: pulse,
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
        // 強化通常攻撃の基礎（換算後）。通常攻撃のダメージ × 1.2 に足す（shapeBasicAttack）
        s.units[i].hero!.kit!.zailChargeBonus = Self.enhanceBaseDamage(rank: c.numbers.rank)
        // 突進のダメージ = 基礎 + 50% 追加物理攻撃（発動した時点の値）
        var p = HitPayload(damage: Self.dashDamage(rank: c.numbers.rank, bonusAttack: Self.bonusAttack(s.units[i])),
                           damageType: .physical, source: .skill(.skill2), skillID: c.check.skill.skillID)
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
        // 平均 1 撃（重み 1 = 1・2 撃目 ÷ 0.75）。基礎 + 80% 追加物理攻撃（発動した時点の値）
        let average = Self.ultStrikeDamage(rank: c.numbers.rank, bonusAttack: Self.bonusAttack(s.units[i])) / Tune.ultWeights[0]
        s.units[i].hero!.kit!.zailUltDamage = average
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
            // 強化通常攻撃の射程（公式 2.5 = 250）。強化が残っている間だけ通常攻撃の射程を伸ばす
            let bonus = Tune.enhanceRange - (ctx.master.hero(heroID)?.attackRange ?? Tune.enhanceRange)
            if bonus > 0 {
                Kit.grantAttackRange(&s, target: owner, amount: bonus, duration: Tune.enhanceWindow,
                                     tag: Tune.enhanceRangeTag)
            }
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

    /// 剣撃: 主対象にダメージ + S2 のクールダウン短縮、軌道上の他の敵に 50%。ヒーロー以外（ミニオン・モンスター）には 50%。
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
        // 主対象・軌道上の敵が確定してからヒーロー以外の割合を決める（命中中に種類は変わらない）
        let mainScale = Self.nonHeroScale(s.units[t].kind)
        // 剣撃 1 本ごとに S2 のクールダウン −1 秒・S1 自身のクールダウン −0.5 秒（日本語クライアント）
        let main = HitPayload(damage: timer.param * mainScale, damageType: .physical, source: .skill(.skill1),
                              skillID: skillID, effects: [.refundCooldown(slot: .skill2, seconds: Tune.chargeRefund),
                                                          .refundCooldown(slot: .skill1, seconds: Tune.swordsRefund)])
        CombatSystem.applyHit(&s, ctx, sourceID: ownerID, team: team, targetIndex: t, payload: main, from: me)
        guard CombatSystem.isLiving(s, owner) else { return }
        for j in others {
            let pass = HitPayload(damage: timer.param * Tune.strikePassRatio * Self.nonHeroScale(s.units[j].kind),
                                  damageType: .physical, source: .skill(.skill1), skillID: skillID)
            CombatSystem.applyHit(&s, ctx, sourceID: ownerID, team: team, targetIndex: j, payload: pass, from: me)
        }
    }

    /// 剣撃のダメージの割合: ヒーロー（と練習場の人形）は 1、それ以外の敵（ミニオン・モンスター）は公式の 50%。
    static func nonHeroScale(_ kind: UnitKind) -> Double {
        switch kind {
        case .hero, .dummy: return 1
        default: return Tune.strikeNonHeroRatio
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
        // 三連撃の間は動かない。打ち上げたあとは制圧（suppress）でのみ中断される（公式。スタンなどでは止まらない）
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
                           param: k.zailUltDamage, interruptible: false)
    }

    /// 奥義の 1 撃。対象が倒れた・離れすぎた・術者が制圧されたら残りを取り消して終える。3 撃目は剣撃を乗せない。
    private func ultStrike(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard s.units[owner].hero?.kit?.zailUltPhase == 2 else { return }
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), s.units[t].team != s.units[owner].team,
              !s.units[owner].has(.suppress)
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
        // 打ち上げたあとの三連撃は制圧（suppress）でのみ中断される（スタンなどは予約を消さない）
        if k.zailUltPhase == 2, s.units[owner].has(.suppress) {
            Kit.cancelScheduled(&s, caster: owner, slot: .ultimate, code: Code.ultStrike)
            endUlt(&s, owner)
            return
        }
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
        // 突進中のハード CC: 突進は取り消し済み。奥義の状態を畳む（クールダウンは戻らない）。
        // 三連撃（段 2）の予約は中断されない（interruptible: false）ので、ここでは畳まない（制圧だけが update で止める）
        guard s.units[owner].hero?.kit?.zailUltPhase == 1 else { return }
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
        // 強化通常攻撃（1 回で消える）: 通常攻撃を「基礎 + 物理攻撃の 120%」に置き換える
        // = 通常攻撃のダメージ（物理攻撃 × 会心）× 1.2 + 基礎（換算後）。鈍足 60% 1 秒。射程の延長も消す
        plan.payload.damage = plan.payload.damage * Tune.enhanceAttackRatio + k.zailChargeBonus
        plan.payload.statuses.append(StatusEffect(kind: .slow, duration: Tune.slowDuration, magnitude: Tune.slowAmount,
                                                  sourceID: s.units[attacker].id, tag: Tune.slowTag))
        s.units[attacker].hero!.kit!.zailChargeWindow = 0
        s.units[attacker].statuses.removeAll { $0.kind == .attackRangeBoost && $0.tag == Tune.enhanceRangeTag }
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

    /// 1 層あたりの防御ダウン（固定値）。公式のレベル別の表（Lv1〜3 = 3、Lv4〜6 = 4、…、Lv15 = 8）。
    static func baneFlat(level: Int) -> Double {
        Tune.baneByLevel[min(max(1, level), Tune.baneByLevel.count) - 1]
    }

    // MARK: - ダメージ（公式の表 → sim の式）

    /// 公式の基礎ダメージ（ランクで補間）を sim の通常の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), slot: SkillSlot, scale: Double, rank: Int, maxRank: Int) -> Double {
        lerp(table.0, table.1, rank: rank, maxRank: maxRank) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の「+N% 物理攻撃」を sim の通常の式（× skillAttackScalingFactor × スロット倍率 × 換算）に通した、攻撃力に対する割合（%）。
    static func attackPercent(_ ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * Balance.skillAttackScalingFactor * Balance.Skills.damageScale(slot) * scale * 100
    }

    /// (公式の基礎 + 係数 × 追加物理攻撃 × skillAttackScalingFactor) × スロット倍率 × 換算。
    /// bonusAttack = 追加物理攻撃（装備・バフで増えた分。`bonusAttack(_:)`）。numbers（HUD・説明文）は 0 = 装備なしの値。
    private static func damage(base: (Double, Double), ratio: Double, slot: SkillSlot, scale: Double, rank: Int,
                               bonusAttack: Double) -> Double {
        let b = lerp(base.0, base.1, rank: rank, maxRank: slot.maxRank)
        return (b + ratio * max(0, bonusAttack) * Balance.skillAttackScalingFactor) * Balance.Skills.damageScale(slot) * scale
    }

    /// 追加物理攻撃（物理攻撃 − レベルの基礎値。装備・バフで増えた分。H032 と同じ）。
    static func bonusAttack(_ u: Unit) -> Double { max(0, u.stats.attack - u.baseStats.attack) }

    /// S1 の接触 1 回（75 → 125 + 25% 追加物理攻撃）。
    static func contactDamage(rank: Int, bonusAttack: Double = 0) -> Double {
        damage(base: Tune.contactBase, ratio: Tune.contactAttackRatio, slot: .skill1, scale: Tune.swordsScale, rank: rank,
               bonusAttack: bonusAttack)
    }

    /// S1 の剣撃 1 本（主対象。200 → 300 + 50% 追加物理攻撃）。
    static func strikeDamage(rank: Int, bonusAttack: Double = 0) -> Double {
        damage(base: Tune.strikeBase, ratio: Tune.strikeAttackRatio, slot: .skill1, scale: Tune.swordsScale, rank: rank,
               bonusAttack: bonusAttack)
    }

    /// S2 の突進（75 → 150 + 50% 追加物理攻撃）。
    static func dashDamage(rank: Int, bonusAttack: Double = 0) -> Double {
        damage(base: Tune.dashBase, ratio: Tune.dashAttackRatio, slot: .skill2, scale: Tune.chargeScale, rank: rank,
               bonusAttack: bonusAttack)
    }

    /// S2 の強化通常攻撃の基礎（75 → 150 を突進と同じ換算に通した値）。通常攻撃のダメージ × 1.2 に足す。
    static func enhanceBaseDamage(rank: Int) -> Double {
        scaledBase(Tune.enhanceBase, slot: .skill2, scale: Tune.chargeScale, rank: rank, maxRank: SkillSlot.skill2.maxRank)
    }

    /// 奥義の 1・2 撃目（120 / 170 / 220 + 80% 追加物理攻撃）。3 撃目はちょうど 2 倍（240 / 340 / 440 + 160%）。
    static func ultStrikeDamage(rank: Int, bonusAttack: Double = 0) -> Double {
        damage(base: Tune.ultStrikeBase, ratio: Tune.ultStrikeAttackRatio, slot: .ultimate, scale: Tune.ultScale,
               rank: rank, bonusAttack: bonusAttack)
    }

    /// 公式のクールダウン（秒）をランクで線形補間し、CD 短縮を掛ける（全体倍率 cooldownScale は 1.0 = 公式の秒数のまま）。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        let sec = lerp(range.0, range.1, rank: rank, maxRank: maxRank)
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H028", slot: slot)?.skillID
    }
}
