import Foundation

// 担当: kit-H033（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Alucard.md）
// H033 紅牙のヴァルド = Velstria 版の Alucard（MLBB。調査: docs/kits/Alucard.md、対応表: 同ファイル末尾）。
// 数値の正は MLBB Fandom の現行のスキル表（docs/kits/Alucard.md の「公式（MLBB Fandom 現行）の数値」）。
// アサシン（ジャングル）の近接。キットはロールの汎用パッシブ（奇襲 +30% とキル/アシストの全 CD −30%）を置き換える。
// 公式はスキルにコストが無い（HeroKit.cost で 0）。
//   パッシブ 追撃（Pursuit）            — スキルを発動するたび、5 秒以内の次の通常攻撃が「追撃」になる: 射程 400（公式 4）まで伸び、
//                                          敵の目の前まで踏み込みながら物理攻撃の 125% の物理ダメージ。
//   S1   裂地撃（Groundsplitter）       — 指定した地点へ転がり込み、大剣を叩きつける。270 → 370（+80% 物理攻撃）+ 鈍足 40%（2 秒）。
//                                          ボットはミニオン・ジャングルにも使う（botFarm）。
//   S2   旋回斬（Whirling Smash）       — その場で大剣を回転させ、周囲の敵に 345 → 570（+120%）（照準なし）。
//   奥義 核分裂波（Fission Wave）       — 1 回目: 指定地点の範囲の敵のエネルギーを吸収（鈍足 30%・複合防御 −10 / 15 / 20、4 秒）。
//                                          敵ヒーロー 1 体につき自分に複合防御 +10 / 15 / 20、6 秒間 S1・S2 のクールダウンが半分。
//                                          6 秒以内の再使用（同じ castSkill）で、向きへ貫通する衝撃波 400 / 550 / 700（+200%）。
//                                          奥義を習得している間は常に複合吸血（通常攻撃 10 / 20 / 30%、スキルはその 0.33 倍）。
// 数値の換算: 公式の表を Velstria のランクへ線形補間し、sim の通常の式 (基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率 に
//   スキルごとの換算（Tune.*Scale）を掛ける（H029 と同じ）。「追加物理攻撃」の係数は総攻撃力に掛ける。
//
// 状態（KitState）:
//   timers[0] = 追撃の残り秒（>0 = 次の通常攻撃が追撃）   timers[1] = 奥義のクールダウン半減の残り秒
//   reals[0]  = S1 の着地で与えるダメージ（転がっている間だけ持つ）
//   ints[0]   = 追撃の累計回数（検証用）   ints[1] = 吸収の累計回数   ints[2] = 直近の吸収で捉えた敵ヒーローの数
//   ints[3]   = 衝撃波の累計回数          ints[4] = 地割りの着地の累計回数

extension KitState {
    var valdPursuit: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var valdHaste: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var valdSlamDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }

    var valdPursuits: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var valdAbsorbs: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var valdAbsorbHeroes: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var valdWaves: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var valdSlams: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }
}

struct Kit_H033: HeroKit {
    let heroID = "H033"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H033(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100 を近接スキルの射程に合わせて調整）

    enum Tune {
        // パッシブ 追撃
        /// 追撃のダメージ（物理攻撃の 125%。Fandom・Liquipedia の現行。mlbb.io の 140% は採らない）。
        static let pursuitRatio = 1.25
        /// 公式に記載なし: スキルの発動から追撃を使えるまでの猶予。
        static let pursuitWindow = 5.0
        /// 追撃のために射程が伸びる量（公式の強化通常攻撃の射程 4 = 400。通常攻撃 150 → 400）。踏み込める距離。
        static let pursuitRangeBonus = 250.0
        static let pursuitDashSpeed = 2600.0
        /// 踏み込みで止まる位置（半径の和 + この値）。
        static let pursuitGap = 5.0
        static let pursuitRangeTag = KitTags.buff("H033", "pursuitRange")

        // 吸血（奥義のパッシブ。調査: 10% 一定 / 10・20・30% で割れている → 奥義ランクで伸びる 10 / 20 / 30% を採る）
        static let hybridLifesteal: [Double] = [0.10, 0.20, 0.30]
        /// スキルのダメージの吸血は通常攻撃の何倍か。MLBB の複合吸血は範囲スキルが 1/3、単体は等倍。
        /// Velstria のスペルヴァンプは命中した対象ごとに全量（範囲スキルで大勢に当てると回復が人数倍になる）ので、
        /// 範囲スキルの 1/3 に合わせた。S1・S2 はどちらも範囲で、ジャングルの周回での回復が過大にならない。
        static let spellVampFactor = 0.33
        static let lifestealTag = KitTags.buff("H033", "lifesteal")
        static let spellVampTag = KitTags.buff("H033", "spellVamp")
        /// 常時効果のステータスに持たせる持続（実質無期限）。
        static let permanent: Double = 1_000_000

        // S1 地割り
        /// 転がる距離の最大（調査に「不明」。近接スキルの標準 ≈ 300 に少し足した）。
        static let s1Range = 350.0
        /// 着地で叩きつける範囲の半径。
        static let s1Radius = 190.0
        static let s1Speed = 1800.0
        /// 対象を指定したときに、対象の縁の手前で止まる余裕。
        static let s1Gap = 5.0
        static let s1Slow = 0.40
        static let s1SlowDuration = 2.0
        static let s1SlowTag = KitTags.buff("H033", "slow")
        /// 公式: 270 → 370（+80% 追加物理攻撃。Liquipedia は +85%）。Lv1 → Lv6 を最大ランクへ線形補間。
        static let s1Base = (270.0, 370.0)
        static let s1AttackRatio = 0.8
        /// 公式の値 → Velstria の換算（sim の通常の式 × スロット倍率の後ろに掛ける）。Lv1〜3 はスキル1 しか無いので、
        /// Lv1 の勝率がほぼこの値で決まる（docs/kits/Alucard.md の「バランス」）。
        static let s1Scale = 0.66

        // S2 旋回斬
        static let s2Radius = 250.0
        /// 公式: 345 → 570（+120% 追加物理攻撃）。
        static let s2Base = (345.0, 570.0)
        static let s2AttackRatio = 1.2
        /// 公式の値 → Velstria の換算。1 発は汎用の S2 の約 0.15 倍（予算 0.8〜1.3 倍を大きく割る）: クールダウンが公式の 6 → 4 秒
        /// （汎用の S2 = 9.8 秒の約半分）で、アルティメットの半減中はさらに半分、公式どおりコストも無いので、何度でも撃てて
        /// そのたびに追撃（物理攻撃 125% の踏み込み）と吸血が乗る。Lv12 の勝率は S2 の値に最も敏感（0.01 で約 3 pt）なので、勝率で決めた。
        static let s2Scale = 0.08

        // 奥義 核分裂波
        /// 吸収の中心を置ける距離と、吸収の半径。
        static let ultCastRange = 450.0
        static let absorbRadius = 300.0
        static let absorbSlow = 0.30
        /// 敵の複合防御（物理防御・魔法防御）を下げる固定値（公式 10 / 15 / 20）と、鈍足・防御ダウンの持続（公式に記載なし）。
        static let absorbDefense = (10.0, 20.0)
        static let absorbDuration = 4.0
        /// 敵ヒーロー 1 体につき自分が得る複合防御（公式 10 / 15 / 20。`flatDefenseMod`、hasteDuration の間）。
        static let defensePerHero = (10.0, 20.0)
        /// S1・S2 のクールダウンが半分になる秒数（公式 6 秒）と、再使用の窓（公式に記載なし: 6 秒を選んだ）。
        static let hasteDuration = 6.0
        static let ultWindow = 6.0
        static let hasteTag = KitTags.buff("H033", "defense")
        static let shredTag = KitTags.buff("H033", "shred")
        static let absorbSlowTag = KitTags.buff("H033", "absorbSlow")
        /// 衝撃波: 長さ・半幅・速さ（公式に記載なし。データ上の奥義の射程 600 を長い波へ伸ばした）。
        static let waveRange = 900.0
        static let waveHalfWidth = 130.0
        static let waveSpeed = 2200.0
        /// 公式: 衝撃波 400 / 550 / 700（+200% 追加物理攻撃）。アルティメットの 3 ランク = 公式の Lv1〜3 そのまま。
        static let waveBase = (400.0, 700.0)
        static let waveAttackRatio = 2.0
        /// 公式の値 → Velstria の換算。衝撃波は汎用の奥義の約 0.55 倍（予算 0.8〜1.3 倍を割る）: 吸収で複合防御 +20/体・敵 −20、
        /// 6 秒のクールダウン半減、コスト 0 が公式の値になって Lv12 が同ロール中央値 +31 pt まで強くなったので、勝率で下げた。
        static let waveScale = 0.34

        // クールダウン（公式の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）。
        static let s1Cooldown = (8.5, 6.5)
        static let s2Cooldown = (6.0, 4.0)
        static let ultCooldown = (40.0, 30.0)
    }

    /// KitTimer.code
    private enum Code {
        static let slam = 1
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 指定地点へ転がって叩きつける（跳躍の archetype。着地の範囲は転がり終えた tick に自前で当てる）
            return SkillTargeting(archetype: .leapSlam, aim: .point, range: Tune.s1Range, radius: Tune.s1Radius,
                                  shape: .circleAtPoint)
        case .skill2:
            // 照準なしの自分中心の範囲
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.s2Radius, shape: .selfRing)
        case .ultimate:
            if stage >= 1 {
                // 衝撃波: 向きへ貫通する長い直線。radius は半幅
                return SkillTargeting(archetype: .piercingLine, aim: .direction, range: Tune.waveRange,
                                      radius: Tune.waveHalfWidth, shape: .wideLine, recastable: true)
            }
            // 吸収: 指定地点の範囲（地点 AoE）。radius は吸収の半径
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: Tune.ultCastRange,
                                  radius: Tune.absorbRadius, shape: .circleAtPoint, recastable: true)
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
            n.extras = [KitStat(key: "pursuit", value: Tune.pursuitRatio * 100),
                        KitStat(key: "window", value: Tune.pursuitWindow),
                        KitStat(key: "reachMult", value: (hero.attackRange + Tune.pursuitRangeBonus) / hero.attackRange)]
        case .skill1:
            n.damage = Self.s1Damage(rank: rank, stats: stats)
            n.hits = 1
            n.cc = .slow
            n.ccIsUltimate = false
            n.ccDuration = Tune.s1SlowDuration
            n.cooldown = Self.cooldown(Tune.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "slow", value: Tune.s1Slow * 100),
                        KitStat(key: "slowDuration", value: Tune.s1SlowDuration),
                        KitStat(key: "base", value: Self.scaledBase(Tune.s1Base, slot: .skill1, scale: Tune.s1Scale,
                                                                    rank: rank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.s1AttackRatio, slot: .skill1,
                                                                         scale: Tune.s1Scale).rounded())]
        case .skill2:
            n.damage = Self.s2Damage(rank: rank, stats: stats)
            n.hits = 1
            n.cc = .none
            n.ccDuration = 0
            n.cooldown = Self.cooldown(Tune.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "base", value: Self.scaledBase(Tune.s2Base, slot: .skill2, scale: Tune.s2Scale,
                                                                    rank: rank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.s2AttackRatio, slot: .skill2,
                                                                         scale: Tune.s2Scale).rounded())]
        case .ultimate:
            // damage = 衝撃波のダメージ（吸収そのものにダメージは無い。説明・予算の基準として 1 回目にも載せる）
            n.damage = Self.waveDamage(rank: rank, stats: stats)
            n.hits = 1
            n.missingHealthRatio = 0
            n.cc = stage >= 1 ? .none : .slow
            n.ccIsUltimate = false
            n.ccDuration = stage >= 1 ? 0 : Tune.absorbDuration
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.stages = 2
            n.recastWindow = Tune.ultWindow
            n.extras = [KitStat(key: "slow", value: Tune.absorbSlow * 100),
                        KitStat(key: "defense", value: Self.absorbDefense(rank: rank)),
                        KitStat(key: "haste", value: Tune.hasteDuration),
                        KitStat(key: "lifesteal", value: Self.lifesteal(rank: rank) * 100),
                        KitStat(key: "gain", value: Self.defensePerHero(rank: rank)),
                        KitStat(key: "debuff", value: Tune.absorbDuration),
                        KitStat(key: "window", value: Tune.ultWindow),
                        KitStat(key: "vampPct", value: Tune.spellVampFactor * 100),
                        KitStat(key: "base", value: Self.scaledBase(Tune.waveBase, slot: .ultimate, scale: Tune.waveScale,
                                                                    rank: rank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.waveAttackRatio, slot: .ultimate,
                                                                         scale: Tune.waveScale).rounded())]
        }
        return n
    }

    /// 公式はスキルにコストが無い（MLBB の Alucard は資源を持たない）。Energy のバーは残るが、どのスキルも消費しない。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        slot == .passive ? base : 0
    }

    /// 説明文は公式の文の構造に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%物理攻撃) は sim の式に換算した値）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "スキルを発動するたびに、次の通常攻撃（{window}秒以内。射程は近接攻撃の約{reachMult}倍）で対象の位置へ踏み込み、(+{pursuit}%物理攻撃)の物理ダメージを与える。",
                en: "After each skill cast, Vald's next basic attack (within {window}s, reaching about {reachMult}x the melee attack range) lets him dash to the target's location and deal (+{pursuit}% Physical Attack) physical damage.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "指定エリアへ跳び込んで斬りつけ、命中した敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与え、移動速度を{slowDuration}秒間{slow}%低下させる。",
                en: "Leap to the target area and slash, dealing {base} (+{atkPct}% Physical Attack) physical damage to enemies hit and slowing them by {slow}% for {slowDuration}s.",
                tags: [KitTag.mobility, KitTag.aoe])
        case .skill2:
            return KitText(
                ja: "回転斬りを放ち、周囲の敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与える。",
                en: "Launch a whirling slash, dealing {base} (+{atkPct}% Physical Attack) physical damage to nearby enemies.",
                tags: [KitTag.aoe])
        case .ultimate:
            return KitText(
                ja: "パッシブ：常に{lifesteal}%の複合吸血を得る（スキルのダメージの吸血はその{vampPct}%）。\n\n"
                    + "アクティブ：指定エリアの敵のエネルギーを吸収し、{debuff}秒間 移動速度を{slow}%、複合防御を{defense}低下させる。命中した敵ヒーロー1体につき複合防御を{gain}得て、{haste}秒間 他のスキルのクールダウンを50%にする。\n\n"
                    + "再発動：{window}秒以内に指定方向へ強力な衝撃波を放ち、命中した敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与える。",
                en: "Passive: Vald permanently gains {lifesteal}% Hybrid Lifesteal ({vampPct}% of that on skill damage).\n\n"
                    + "Active: absorb the energy of enemies in the target area, reducing their Movement Speed by {slow}% and Hybrid Defense by {defense} for {debuff}s. Vald gains {gain} Hybrid Defense for each enemy hero hit and reduces the cooldown of his other skills to 50% for {haste}s.\n\n"
                    + "Use Again: within {window}s, release a powerful shockwave in the target direction, dealing {base} (+{atkPct}% Physical Attack) physical damage to enemies hit.",
                tags: [KitTag.buff, KitTag.burst])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 追撃の準備ができている間は残り時間
            guard k.valdPursuit > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.valdPursuit, total: Tune.pursuitWindow)
        case .ultimate:
            // クールダウン半減の残り時間
            guard k.valdHaste > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.valdHaste, total: Tune.hasteDuration)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castGroundsplitter(&s, ctx, c)
        case .skill2: castWhirlingSmash(&s, ctx, c)
        case .ultimate: castAbsorb(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 指定地点へ転がる。経路の敵には当たらず、転がり終えた tick に 1 度だけ範囲を叩く（onTimer）。
    private func castGroundsplitter(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let from = s.units[i].pos
        var travel = c.aim.distance
        if let u = c.aim.unit {
            // 対象を指定したときは対象の縁（自分の半径込み）の手前で止まる（中心が重ならない）
            let gap = s.units[i].radius + s.units[u].radius + Tune.s1Gap
            travel = max(0, from.distance(to: s.units[u].pos) - gap)
        }
        travel = min(Tune.s1Range, max(0, travel))
        let dir = c.aim.direction
        s.units[i].hero!.kit!.valdSlamDamage = c.numbers.damage
        // 経路上の敵には当たらない（affectsEnemies = false）。ハード CC の中断と着地の通知だけを使う
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.skill1), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill1, to: from + dir * travel,
                                       speed: Tune.s1Speed, payload: carrier, radius: 0, arriveCode: Code.slam)
        Kit.emitCast(&s, c, origin: from, target: landing, unit: c.aim.unit, shape: .circleAtPoint,
                     duration: from.distance(to: landing) / Tune.s1Speed, count: 1)
    }

    /// S2: 自分中心の円。即時。
    private func castWhirlingSmash(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let center = s.units[i].pos
        Kit.emitCast(&s, c, origin: center, target: center, shape: .selfRing, count: 1)
        var p = HitPayload(damage: c.numbers.damage, damageType: .physical, source: .skill(.skill2),
                           skillID: c.check.skill.skillID)
        p.originPos = center
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: center, radius: Tune.s2Radius, shape: .circle, payload: p)
    }

    /// 奥義の 1 回目: 範囲の敵を吸収（鈍足・防御ダウン）。敵ヒーローの数だけ被ダメ軽減を得て、S1・S2 のクールダウンを半減させる。
    private func castAbsorb(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        let center = c.aim.point
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: center, unit: c.aim.unit, shape: .circleAtPoint,
                     duration: Tune.ultWindow, count: 1)
        let skillID = c.check.skill.skillID
        let rank = c.numbers.rank
        let shred = Self.absorbDefense(rank: rank)
        let hit = Kit.hitAreaEach(&s, ctx, caster: i, center: center, radius: Tune.absorbRadius, shape: .circle) { _, _ in
            // 複合防御（物理防御と魔法防御）を固定値で下げる（公式 10 / 15 / 20）
            let statuses = [
                StatusEffect(kind: .slow, duration: Tune.absorbDuration, magnitude: Tune.absorbSlow, sourceID: id,
                             tag: Tune.absorbSlowTag),
                StatusEffect(kind: .flatDefenseMod, duration: Tune.absorbDuration, magnitude: -shred, sourceID: id,
                             tag: Tune.shredTag),
            ]
            var p = HitPayload(damage: 0, damageType: .physical, source: .skill(.ultimate), statuses: statuses,
                               skillID: skillID)
            p.originPos = center
            return p
        }
        // 無敵の相手は吸収できない（効果が入らないので数えない）
        let heroes = hit.filter { s.units[$0].kind == .hero && !CombatSystem.isInvulnerable(s, ctx, $0) }.count
        s.units[i].hero!.kit!.valdAbsorbs += 1
        s.units[i].hero!.kit!.valdAbsorbHeroes = heroes
        s.units[i].hero!.kit!.valdHaste = Tune.hasteDuration
        if heroes > 0 {
            // 敵ヒーロー 1 体につき複合防御 +10 / 15 / 20（公式。hasteDuration の間）
            CombatSystem.addStatus(&s, targetIndex: i,
                                   StatusEffect(kind: .flatDefenseMod, duration: Tune.hasteDuration,
                                                magnitude: Self.defensePerHero(rank: rank) * Double(heroes), sourceID: id,
                                                tag: Tune.hasteTag))
        }
        Kit.openRecast(&s, caster: i, slot: .ultimate, duration: Tune.ultWindow, stage: 1, charges: 1)
    }

    /// 奥義の 2 回目（再使用）: 向きへ貫通する衝撃波。窓は閉じる（クールダウンは 1 回目で消費済み）。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        guard c.slot == .ultimate else {
            Kit.closeRecast(&s, ctx, caster: c.caster, slot: c.slot)
            return
        }
        let i = c.caster
        let dir = c.aim.direction
        let origin = s.units[i].pos
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.waveRange, unit: c.aim.unit, shape: .wideLine,
                     duration: Tune.waveRange / Tune.waveSpeed, count: 1)
        var p = HitPayload(damage: c.numbers.damage, damageType: .physical, source: .skill(.ultimate),
                           skillID: c.check.skill.skillID)
        p.originPos = origin
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: Tune.waveRange),
                               speed: Tune.waveSpeed, width: Tune.waveHalfWidth, pierce: true, payload: p,
                               visual: c.check.skill.effectID)
        s.units[i].hero!.kit!.valdWaves += 1
        Kit.advanceRecast(&s, ctx, caster: i, slot: .ultimate)
        // 衝撃波もスキルの発動: 追撃の準備（onSkillCast は初回の発動でしか呼ばれない）
        armPursuit(&s, i)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard timer.code == Code.slam, let kit = s.units[owner].hero?.kit else { return }
        s.units[owner].hero!.kit!.valdSlamDamage = 0
        s.units[owner].hero!.kit!.valdSlams += 1
        let center = s.units[owner].pos
        let slow = StatusEffect(kind: .slow, duration: Tune.s1SlowDuration, magnitude: Tune.s1Slow,
                                sourceID: s.units[owner].id, tag: Tune.s1SlowTag)
        var p = HitPayload(damage: kit.valdSlamDamage, damageType: .physical, source: .skill(.skill1),
                           statuses: [slow], skillID: Self.skillID(ctx, .skill1))
        p.originPos = center
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: center, radius: Tune.s1Radius, shape: .circle, payload: p)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        syncHybridLifesteal(&s, owner)
        // 奥義の間は S1・S2 のクールダウンが半分 = 通常の経過に加えて、もう 1 tick ぶん進める
        if k.valdHaste > 0 {
            Kit.refundCooldown(&s, ctx, caster: owner, slot: .skill1, seconds: Balance.dt)
            Kit.refundCooldown(&s, ctx, caster: owner, slot: .skill2, seconds: Balance.dt)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 転がりが止められた: 着地の処理が呼ばれないので記録を捨てる
        s.units[owner].hero?.kit?.valdSlamDamage = 0
    }

    // MARK: - C. パッシブ（追撃・複合吸血）

    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {
        armPursuit(&s, caster)
    }

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard let k = s.units[attacker].hero?.kit, k.valdPursuit > 0 else { return }
        // 追撃は 1 回で使い切る（構造物にも消費するが、威力と踏み込みは乗らない）
        s.units[attacker].hero!.kit!.valdPursuit = 0
        s.units[attacker].statuses.removeAll { $0.kind == .attackRangeBoost && $0.tag == Tune.pursuitRangeTag }
        guard !s.units[target].isStructure else { return }
        plan.payload.damage *= Tune.pursuitRatio
        s.units[attacker].hero!.kit!.valdPursuits += 1
        // 敵の目の前まで踏み込む（ルート中は動けない。壁は手前で止まる）
        guard !s.units[attacker].has(.root) else { return }
        let from = s.units[attacker].pos
        let delta = s.units[target].pos - from
        let gap = s.units[attacker].radius + s.units[target].radius + Tune.pursuitGap
        guard delta.length > gap + 1 else { return }
        MovementSystem.dash(&s, ctx, unitIndex: attacker, to: from + delta.normalized * (delta.length - gap),
                            speed: Tune.pursuitDashSpeed, kind: .dash)
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        guard slot == .ultimate else { return .useDefault }
        let pos = s.units[bot].pos
        let foe = s.units[target]
        if Kit.window(s, caster: bot, slot: .ultimate) != nil {
            // 2 回目: 衝撃波が届く距離に居れば撃つ
            guard pos.distance(to: foe.pos) <= Tune.waveRange + foe.radius else { return .skip }
            return .cast(.unit(foe.id))
        }
        // 1 回目: 交戦中に、吸収の円が敵に届くときだけ（吸収は即時なので予測は要らない）
        guard fighting, pos.distance(to: foe.pos) <= Tune.ultCastRange + Tune.absorbRadius else { return .skip }
        return .cast(.point(foe.pos))
    }

    /// ミニオン・ジャングルの集団にも裂地撃（S1）を使ってよいか。Lv1〜3 はスキル1 しか無く、通常攻撃だけではキャンプが遅いので、
    /// 転がり込んで叩きつける。HP が半分以上で、着地点が敵のタワー・コアの射程に入らないときだけ。
    func botFarm(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 center: Vec2, count: Int) -> Bool {
        guard slot == .skill1, s.units[bot].hpRatio >= 0.5 else { return false }
        for u in s.units where u.isStructure && u.isAlive && u.team != s.units[bot].team {
            let r = Balance.towerRange + Balance.heroRadius + 120
            if u.pos.distanceSquared(to: center) <= r * r { return false }
        }
        return true
    }

    // MARK: - 部品

    /// 追撃の準備（スキルを発動するたび）。射程が伸び、猶予の間だけ有効。
    private func armPursuit(_ s: inout SimState, _ i: Int) {
        guard s.units[i].hero?.kit != nil else { return }
        s.units[i].hero!.kit!.valdPursuit = Tune.pursuitWindow
        Kit.grantAttackRange(&s, target: i, amount: Tune.pursuitRangeBonus, duration: Tune.pursuitWindow,
                             tag: Tune.pursuitRangeTag)
    }

    /// 奥義を習得している間の常時効果: 複合吸血（通常攻撃の吸血 + スキルの吸血）。ランクが上がれば大きさだけ更新する。
    private func syncHybridLifesteal(_ s: inout SimState, _ i: Int) {
        let rank = min(max(0, s.units[i].hero?.rank(.ultimate) ?? 0), Tune.hybridLifesteal.count)
        let life = Self.lifesteal(rank: rank)
        sync(&s, i, kind: .lifestealBoost, tag: Tune.lifestealTag, want: life)
        sync(&s, i, kind: .spellVampBoost, tag: Tune.spellVampTag, want: life * Tune.spellVampFactor)
    }

    private func sync(_ s: inout SimState, _ i: Int, kind: StatusKind, tag: String, want: Double) {
        if let k = s.units[i].statuses.firstIndex(where: { $0.kind == kind && $0.tag == tag }) {
            if want <= 0 {
                s.units[i].statuses.remove(at: k)
            } else if s.units[i].statuses[k].magnitude != want {
                s.units[i].statuses[k].magnitude = want
            }
        } else if want > 0 {
            switch kind {
            case .lifestealBoost: Kit.grantLifesteal(&s, target: i, ratio: want, duration: Tune.permanent, tag: tag)
            default: Kit.grantSpellVamp(&s, target: i, ratio: want, duration: Tune.permanent, tag: tag)
            }
        }
    }

    // MARK: - ダメージ（公式の表 → sim の式）

    /// 公式の基礎ダメージ（ランクで補間）を sim の通常の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), slot: SkillSlot, scale: Double, rank: Int) -> Double {
        lerp(table, rank: rank, maxRank: slot.maxRank) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の「+N% 物理攻撃」を sim の通常の式（× skillAttackScalingFactor × スロット倍率 × 換算）に通した、攻撃力に対する割合（%）。
    static func attackPercent(_ ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * Balance.skillAttackScalingFactor * Balance.Skills.damageScale(slot) * scale * 100
    }

    /// (公式の基礎 + 係数 × 攻撃力 × skillAttackScalingFactor) × スロット倍率 × 換算。
    private static func damage(base: (Double, Double), ratio: Double, slot: SkillSlot, scale: Double, rank: Int,
                               stats: Stats) -> Double {
        (lerp(base, rank: rank, maxRank: slot.maxRank) + ratio * stats.attack * Balance.skillAttackScalingFactor)
            * Balance.Skills.damageScale(slot) * scale
    }

    /// S1 の叩きつけ（270 → 370 + 80% 物理攻撃）。
    static func s1Damage(rank: Int, stats: Stats) -> Double {
        damage(base: Tune.s1Base, ratio: Tune.s1AttackRatio, slot: .skill1, scale: Tune.s1Scale, rank: rank, stats: stats)
    }

    /// S2 の回転斬り（345 → 570 + 120% 物理攻撃）。
    static func s2Damage(rank: Int, stats: Stats) -> Double {
        damage(base: Tune.s2Base, ratio: Tune.s2AttackRatio, slot: .skill2, scale: Tune.s2Scale, rank: rank, stats: stats)
    }

    /// 奥義の衝撃波（400 / 550 / 700 + 200% 物理攻撃）。
    static func waveDamage(rank: Int, stats: Stats) -> Double {
        damage(base: Tune.waveBase, ratio: Tune.waveAttackRatio, slot: .ultimate, scale: Tune.waveScale, rank: rank,
               stats: stats)
    }

    /// 吸収で敵の複合防御を下げる量（10 / 15 / 20）と、敵ヒーロー 1 体につき自分が得る複合防御（10 / 15 / 20）。
    static func absorbDefense(rank: Int) -> Double {
        lerp(Tune.absorbDefense, rank: rank, maxRank: SkillSlot.ultimate.maxRank)
    }

    static func defensePerHero(rank: Int) -> Double {
        lerp(Tune.defensePerHero, rank: rank, maxRank: SkillSlot.ultimate.maxRank)
    }

    static func lerp(_ range: (Double, Double), rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return range.0 }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return range.0 + (range.1 - range.0) * t
    }

    /// 奥義ランク（0 = 未習得）に応じた通常攻撃の吸血率。
    static func lifesteal(rank: Int) -> Double {
        guard rank > 0 else { return 0 }
        return Tune.hybridLifesteal[min(rank, Tune.hybridLifesteal.count) - 1]
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
        ctx.master.skill(hero: "H033", slot: slot)?.skillID
    }
}
